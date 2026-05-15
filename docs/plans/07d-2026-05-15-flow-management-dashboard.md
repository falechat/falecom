# Plan 07d: Flow Management Dashboard

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans`.
> **Spec:** [07 — Flow Engine](../specs/07-flow-engine.md)
> **Date:** 2026-05-15
> **Status:** Draft — awaiting approval
> **Branch:** `plan-07d-flow-management-dashboard`
> **Depends on:** Plan 07a (models), Plan 07b (engine), Plan 07c (ingestion integration).

**Goal:** Form-based CRUD for `Flow` and `FlowNode` under `/dashboard/flows` (admin-only, per Spec 06e admin patterns), plus `POST /dashboard/channels/:id/activate_flow` and `DELETE /dashboard/channels/:id/deactivate_flow` to bind a flow to a channel. No visual canvas — Spec 07 §2.8 says forms only. Closes Spec 07.

**Architecture:** Reuse `RequireAdmin` concern + `Admin::BaseController` from Plan 06e (the routes go under `/dashboard/flows` per Spec 07 §2.8, but the controllers require admin role; rename the namespace if it makes the route clearer, otherwise gate at the controller). `FlowsController` lists/creates/destroys flows; per-flow show page lists nodes in execution order following `next_node_id` from `root_node`. `FlowNodesController` (nested) handles add/edit/delete with a single form that varies fields by `node_type` (chosen via dropdown, swapped via Turbo Frame). `ChannelFlowActivationsController` toggles `channel.active_flow_id`. Delete-flow guard: `Channel.where(active_flow_id: flow.id).exists?` → 422.

**Tech Stack:** Ruby 4.0.2, Rails 8.1.3, ViewComponent, Tailwind, Hotwire. No new gems.

---

## Files to touch

### Create — controllers / routes

- `packages/app/app/controllers/dashboard/flows_controller.rb`
- `packages/app/app/controllers/dashboard/flows/nodes_controller.rb`
- `packages/app/app/controllers/dashboard/channels/flow_activations_controller.rb`

### Create — views

- `packages/app/app/views/dashboard/flows/index.html.erb`
- `packages/app/app/views/dashboard/flows/new.html.erb`
- `packages/app/app/views/dashboard/flows/show.html.erb` — edit page (flow metadata + nodes list + add-node form)
- `packages/app/app/views/dashboard/flows/_form.html.erb`
- `packages/app/app/views/dashboard/flows/nodes/_node_card.html.erb`
- `packages/app/app/views/dashboard/flows/nodes/_form.html.erb`
- `packages/app/app/views/dashboard/flows/nodes/_fields_message.html.erb`
- `packages/app/app/views/dashboard/flows/nodes/_fields_menu.html.erb`
- `packages/app/app/views/dashboard/flows/nodes/_fields_collect.html.erb`
- `packages/app/app/views/dashboard/flows/nodes/_fields_handoff.html.erb`
- `packages/app/app/views/dashboard/flows/nodes/_fields_branch.html.erb`

### Create — Stimulus

- `packages/app/app/frontend/controllers/node_type_swap_controller.js` — swap fields partial when `node_type` dropdown changes (Turbo Frame target `node-fields`).

### Modify

- `packages/app/config/routes.rb` — add the flow routes under `namespace :dashboard`.

### Tests

- `packages/app/spec/requests/dashboard/flows_spec.rb`
- `packages/app/spec/requests/dashboard/flows/nodes_spec.rb`
- `packages/app/spec/requests/dashboard/channels/flow_activations_spec.rb`

---

## Order of operations

1. **Routes.**
2. **`FlowsController`** — index, new, create, show, update, destroy. Include `RequireAdmin`.
3. **`FlowsController::NodesController`** — create, update, destroy. Same admin gate.
4. **Set-as-root** action (single PATCH on Flow to swap `root_node_id`).
5. **`ChannelFlowActivationsController`** — POST + DELETE.
6. **Views + Stimulus controller for node type swap.**
7. **Regression + PROGRESS (and flip Spec 07 to Shipped).**

Each task ends with a Conventional-Commit commit.

---

## What could go wrong

**Most likely:** the `next_node_id` linking inside the menu form. Each option is `{key, label, next_node_id}`. The form should let the admin pick `next_node_id` from a dropdown of nodes in the same flow. Use a `nested_form`-style array of inputs per option, indexed by position; the controller parses them into an array of hashes before assigning to `content`.

**Least likely:** routes collide with existing `Dashboard::ChannelsController` (none exists — admin handles channels). Safe.

---

## Task 1: Routes

**Files:**
- Modify: `packages/app/config/routes.rb`

- [ ] **Step 1: Add**

```ruby
namespace :dashboard do
  # … existing
  resources :flows do
    member { patch :set_root, to: "flows#set_root" }
    resources :nodes, controller: "flows/nodes"
  end

  resources :channels, only: [] do
    resource :flow_activation, only: [:create, :destroy], controller: "channels/flow_activations"
  end
end
```

- [ ] **Step 2: Verify with `bin/rails routes | grep -E 'flow|nodes'`**.

- [ ] **Step 3: Commit**

```bash
git add packages/app/config/routes.rb
git commit -m "chore(routes): flows + nodes + channel flow_activation routes"
```

---

## Task 2: `Dashboard::FlowsController`

**Files:**
- Create: `packages/app/app/controllers/dashboard/flows_controller.rb`
- Test: `packages/app/spec/requests/dashboard/flows_spec.rb`

- [ ] **Step 1: Failing spec**

```ruby
require "rails_helper"

RSpec.describe "Dashboard::Flows", type: :request do
  let(:admin) { User.create!(name: "A", email_address: "a@x", password: "abcdef12", role: "admin", availability: "offline") }
  let(:agent) { User.create!(name: "B", email_address: "b@x", password: "abcdef12", role: "agent", availability: "offline") }

  describe "as admin" do
    before { sign_in_as(admin) }

    it "GET index lists flows" do
      Flow.create!(name: "Atendimento")
      get dashboard_flows_path
      expect(response.body).to include("Atendimento")
    end

    it "POST creates a flow" do
      expect { post dashboard_flows_path, params: {flow: {name: "Sales", description: "x"}} }
        .to change(Flow, :count).by(1)
    end

    it "PATCH updates flow metadata" do
      f = Flow.create!(name: "f")
      patch dashboard_flow_path(f), params: {flow: {name: "Renamed", inactivity_threshold_hours: 12}}
      expect(f.reload).to have_attributes(name: "Renamed", inactivity_threshold_hours: 12)
    end

    it "DELETE removes flow when no channel binds it" do
      f = Flow.create!(name: "f")
      delete dashboard_flow_path(f)
      expect(Flow.exists?(f.id)).to be false
    end

    it "DELETE 422 when a channel uses it" do
      f = Flow.create!(name: "f")
      Channel.create!(name: "c", channel_type: "whatsapp_cloud", identifier: "c-1", active_flow: f)
      delete dashboard_flow_path(f)
      expect(response).to have_http_status(:unprocessable_content)
      expect(Flow.exists?(f.id)).to be true
    end

    it "PATCH set_root re-points root_node_id" do
      f = Flow.create!(name: "f")
      n = FlowNode.create!(flow: f, node_type: "message", content: {"text" => "x"})
      patch set_root_dashboard_flow_path(f), params: {node_id: n.id}
      expect(f.reload.root_node).to eq(n)
    end
  end

  describe "as non-admin" do
    before { sign_in_as(agent) }
    it "403s" do
      get dashboard_flows_path
      expect(response).to have_http_status(:forbidden)
    end
  end
end
```

- [ ] **Step 2: Implement**

```ruby
module Dashboard
  class FlowsController < ApplicationController
    include RequireAdmin
    before_action :load, only: [:show, :edit, :update, :destroy, :set_root]

    def index = (@flows = Flow.order(:name))
    def new = (@flow = Flow.new)

    def create
      @flow = Flow.new(flow_params)
      if @flow.save
        redirect_to dashboard_flow_path(@flow)
      else
        render :new, status: :unprocessable_content
      end
    end

    def show = (@nodes = @flow.flow_nodes.order(:id))
    def edit = show

    def update
      if @flow.update(flow_params)
        redirect_to dashboard_flow_path(@flow)
      else
        render :show, status: :unprocessable_content
      end
    end

    def destroy
      if Channel.where(active_flow_id: @flow.id).exists?
        render plain: "Flow is bound to a channel — deactivate it first.", status: :unprocessable_content
      else
        @flow.destroy
        redirect_to dashboard_flows_path
      end
    end

    def set_root
      node = @flow.flow_nodes.find(params[:node_id])
      @flow.update!(root_node: node)
      redirect_to dashboard_flow_path(@flow)
    end

    private

    def load = @flow = Flow.find(params[:id])
    def flow_params = params.require(:flow).permit(:name, :description, :is_active, :inactivity_threshold_hours)
  end
end
```

- [ ] **Step 3: Views — `index` + `_form` + `show`** (minimal)

`index.html.erb`:

```erb
<h1 class="text-xl font-semibold mb-3">Flows</h1>
<%= link_to "New flow", new_dashboard_flow_path, class: "btn-primary inline-block mb-3" %>
<table class="w-full text-sm">
  <thead><tr class="border-b text-left"><th>Name</th><th>Active</th><th>Inactivity</th><th></th></tr></thead>
  <tbody>
    <% @flows.each do |f| %>
      <tr class="border-b">
        <td><%= f.name %></td>
        <td><%= f.is_active? ? "✓" : "—" %></td>
        <td><%= f.inactivity_threshold_hours %>h</td>
        <td class="text-right"><%= link_to "Edit", dashboard_flow_path(f) %></td>
      </tr>
    <% end %>
  </tbody>
</table>
```

`new.html.erb`: `<%= render "form" %>`.

`_form.html.erb`:

```erb
<%= form_with model: @flow, url: @flow.persisted? ? dashboard_flow_path(@flow) : dashboard_flows_path do |f| %>
  <% if @flow.errors.any? %><ul class="text-red-600 mb-3"><% @flow.errors.full_messages.each do |m| %><li><%= m %></li><% end %></ul><% end %>
  <%= f.label :name %><%= f.text_field :name, class: "input w-full" %>
  <%= f.label :description %><%= f.text_area :description, class: "input w-full", rows: 3 %>
  <%= f.label :inactivity_threshold_hours %><%= f.number_field :inactivity_threshold_hours, class: "input w-32" %>
  <%= f.check_box :is_active %><%= f.label :is_active %>
  <%= f.submit class: "btn-primary mt-3" %>
<% end %>
```

`show.html.erb`:

```erb
<h1 class="text-xl font-semibold"><%= @flow.name %></h1>
<%= render "form" %>

<h2 class="text-lg mt-6 mb-2">Nodes (<%= @nodes.size %>)</h2>
<ol class="space-y-2">
  <% @nodes.each do |node| %>
    <%= render "dashboard/flows/nodes/node_card", node: node, flow: @flow %>
  <% end %>
</ol>

<h3 class="mt-4">Add node</h3>
<%= render "dashboard/flows/nodes/form", node: FlowNode.new(flow: @flow), flow: @flow %>
```

- [ ] **Step 4: Pass + commit**

```bash
git add packages/app/app/controllers/dashboard/flows_controller.rb \
        packages/app/app/views/dashboard/flows/ \
        packages/app/spec/requests/dashboard/flows_spec.rb
git commit -m "feat(dashboard): Flows CRUD (admin)"
```

---

## Task 3: `Dashboard::Flows::NodesController`

**Files:**
- Create: `packages/app/app/controllers/dashboard/flows/nodes_controller.rb`
- Test: `packages/app/spec/requests/dashboard/flows/nodes_spec.rb`

- [ ] **Step 1: Failing spec**

```ruby
require "rails_helper"

RSpec.describe "Dashboard::Flows::Nodes", type: :request do
  let(:admin) { User.create!(name: "A", email_address: "a@x", password: "abcdef12", role: "admin", availability: "offline") }
  let(:flow)  { Flow.create!(name: "f") }
  before { sign_in_as(admin) }

  it "POST creates a message node" do
    expect {
      post dashboard_flow_nodes_path(flow), params: {flow_node: {node_type: "message", content: {text: "Olá"}.to_json}}
    }.to change(FlowNode, :count).by(1)
    expect(FlowNode.last.content).to eq("text" => "Olá")
  end

  it "POST creates a menu with options array" do
    target = FlowNode.create!(flow: flow, node_type: "handoff", content: {})
    post dashboard_flow_nodes_path(flow), params: {flow_node: {node_type: "menu", content: {
      text: "?",
      options: [{key: "1", label: "Vendas", next_node_id: target.id}]
    }.to_json}}
    n = FlowNode.where(node_type: "menu").last
    expect(n.content["options"].first).to include("key" => "1", "next_node_id" => target.id)
  end

  it "PATCH updates content" do
    n = FlowNode.create!(flow: flow, node_type: "message", content: {"text" => "a"})
    patch dashboard_flow_node_path(flow, n), params: {flow_node: {content: {text: "b"}.to_json}}
    expect(n.reload.content).to eq("text" => "b")
  end

  it "DELETE removes node" do
    n = FlowNode.create!(flow: flow, node_type: "message", content: {})
    expect { delete dashboard_flow_node_path(flow, n) }.to change(FlowNode, :count).by(-1)
  end

  it "DELETE 422 when node is referenced by an active ConversationFlow" do
    n = FlowNode.create!(flow: flow, node_type: "message", content: {})
    channel = Channel.create!(name: "c", channel_type: "whatsapp_cloud", identifier: "c-z")
    contact = Contact.create!; cc = ContactChannel.create!(contact: contact, channel: channel, source_id: "s")
    conv = Conversation.create!(channel: channel, contact: contact, contact_channel: cc, display_id: 42, status: "bot")
    ConversationFlow.create!(conversation: conv, flow: flow, current_node: n, status: "active")
    delete dashboard_flow_node_path(flow, n)
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "422s on malformed JSON content" do
    post dashboard_flow_nodes_path(flow), params: {flow_node: {node_type: "message", content: "{bad"}}
    expect(response).to have_http_status(:unprocessable_content)
  end
end
```

- [ ] **Step 2: Implement**

```ruby
module Dashboard
  module Flows
    class NodesController < ApplicationController
      include RequireAdmin
      before_action :load_flow
      before_action :load_node, only: [:edit, :update, :destroy]

      def create
        @node = @flow.flow_nodes.new(parsed_params)
        if @node.save
          redirect_to dashboard_flow_path(@flow)
        else
          render plain: @node.errors.full_messages.to_sentence, status: :unprocessable_content
        end
      rescue JSON::ParserError => e
        render plain: "content: #{e.message}", status: :unprocessable_content
      end

      def update
        if @node.update(parsed_params)
          redirect_to dashboard_flow_path(@flow)
        else
          render plain: @node.errors.full_messages.to_sentence, status: :unprocessable_content
        end
      rescue JSON::ParserError => e
        render plain: "content: #{e.message}", status: :unprocessable_content
      end

      def destroy
        if ConversationFlow.where(current_node_id: @node.id, status: "active").exists?
          render plain: "Node referenced by an active ConversationFlow.", status: :unprocessable_content
          return
        end
        @node.destroy
        redirect_to dashboard_flow_path(@flow)
      end

      private

      def load_flow = @flow = Flow.find(params[:flow_id])
      def load_node = @node = @flow.flow_nodes.find(params[:id])

      def parsed_params
        raw = params.require(:flow_node).permit(:node_type, :content, :next_node_id)
        raw[:content] = JSON.parse(raw[:content]) if raw[:content].is_a?(String)
        raw
      end
    end
  end
end
```

- [ ] **Step 3: Pass + commit**

```bash
git add packages/app/app/controllers/dashboard/flows/nodes_controller.rb \
        packages/app/spec/requests/dashboard/flows/nodes_spec.rb
git commit -m "feat(dashboard): Flow nodes CRUD"
```

---

## Task 4: `Dashboard::Channels::FlowActivationsController`

**Files:**
- Create: `packages/app/app/controllers/dashboard/channels/flow_activations_controller.rb`
- Test: `packages/app/spec/requests/dashboard/channels/flow_activations_spec.rb`

- [ ] **Step 1: Failing spec**

```ruby
require "rails_helper"
RSpec.describe "Dashboard::Channels::FlowActivations", type: :request do
  let(:admin) { User.create!(name: "A", email_address: "a@x", password: "abcdef12", role: "admin", availability: "offline") }
  let(:channel) { Channel.create!(name: "c", channel_type: "whatsapp_cloud", identifier: "c-fa") }
  let(:flow) { Flow.create!(name: "f") }

  before { sign_in_as(admin) }

  it "POST activates a flow on a channel" do
    post dashboard_channel_flow_activation_path(channel), params: {flow_id: flow.id}
    expect(channel.reload.active_flow).to eq(flow)
  end

  it "DELETE deactivates" do
    channel.update!(active_flow: flow)
    delete dashboard_channel_flow_activation_path(channel)
    expect(channel.reload.active_flow).to be_nil
  end
end
```

- [ ] **Step 2: Implement**

```ruby
module Dashboard
  module Channels
    class FlowActivationsController < ApplicationController
      include RequireAdmin

      def create
        channel = Channel.find(params[:channel_id])
        channel.update!(active_flow_id: params[:flow_id])
        redirect_back fallback_location: admin_channel_path(channel)
      end

      def destroy
        channel = Channel.find(params[:channel_id])
        channel.update!(active_flow_id: nil)
        redirect_back fallback_location: admin_channel_path(channel)
      end
    end
  end
end
```

- [ ] **Step 3: Pass + commit**

```bash
git add packages/app/app/controllers/dashboard/channels/flow_activations_controller.rb \
        packages/app/spec/requests/dashboard/channels/flow_activations_spec.rb
git commit -m "feat(dashboard): channel flow_activation toggle"
```

---

## Task 5: Node form partials + Stimulus swap

**Files:**
- Create: `packages/app/app/views/dashboard/flows/nodes/_form.html.erb`
- Create: `packages/app/app/views/dashboard/flows/nodes/_node_card.html.erb`
- Create: `packages/app/app/views/dashboard/flows/nodes/_fields_<type>.html.erb` (one per node type)
- Create: `packages/app/app/frontend/controllers/node_type_swap_controller.js`

- [ ] **Step 1: `_form.html.erb`**

```erb
<%= form_with model: node, url: node.persisted? ? dashboard_flow_node_path(flow, node) : dashboard_flow_nodes_path(flow), method: node.persisted? ? :patch : :post, data: {controller: "node-type-swap"} do |f| %>
  <%= f.label :node_type %>
  <%= f.select :node_type, %w[message menu collect handoff branch], {selected: node.node_type}, data: {action: "change->node-type-swap#swap"} %>

  <div data-node-type-swap-target="fields">
    <%= render "dashboard/flows/nodes/fields_#{node.node_type || "message"}", node: node, flow: flow %>
  </div>

  <%= f.submit class: "btn-primary mt-3" %>
<% end %>
```

- [ ] **Step 2: One fields partial per type. Example `_fields_message.html.erb`:**

```erb
<%= text_area_tag "flow_node[content]", (node.content.presence || {"text" => ""}).to_json, rows: 3, class: "input w-full font-mono" %>
<p class="text-xs text-gray-500">JSON: { "text": "..." }</p>
```

`_fields_menu.html.erb` (most complex — JSON textarea acceptable for v1; a richer UI is a follow-up):

```erb
<%= text_area_tag "flow_node[content]", (node.content.presence || {"text" => "", "options" => []}).to_json, rows: 8, class: "input w-full font-mono" %>
<p class="text-xs text-gray-500">JSON: { "text": "...", "options": [{ "key": "1", "label": "Vendas", "next_node_id": 42 }] }</p>
```

Same shape for `_fields_collect`, `_fields_handoff`, `_fields_branch` — JSON textarea with example schema in helper text.

- [ ] **Step 3: `_node_card.html.erb`**

```erb
<li class="border rounded p-3" id="<%= dom_id(node) %>">
  <div class="flex justify-between">
    <div>
      <span class="text-xs uppercase font-semibold"><%= node.node_type %></span>
      <span class="text-sm ml-2"><%= node.content["text"] || node.content.to_json.truncate(60) %></span>
    </div>
    <div class="text-sm space-x-2">
      <% if flow.root_node_id == node.id %>
        <span class="text-blue-600">⭐ root</span>
      <% else %>
        <%= button_to "Set as root", set_root_dashboard_flow_path(flow, node_id: node.id), method: :patch, class: "text-xs underline" %>
      <% end %>
      <%= button_to "Delete", dashboard_flow_node_path(flow, node), method: :delete, data: {turbo_confirm: "Delete?"}, class: "text-xs text-red-600" %>
    </div>
  </div>
</li>
```

- [ ] **Step 4: `node_type_swap_controller.js`**

```js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["fields"]

  async swap(event) {
    const type = event.target.value
    const flowId = this.element.action.match(/flows\/(\d+)/)?.[1]
    if (!flowId) return
    const res = await fetch(`/dashboard/flows/${flowId}/nodes/new.fields?node_type=${type}`, { headers: { Accept: "text/html" } })
    if (res.ok) this.fieldsTarget.innerHTML = await res.text()
  }
}
```

Add a small `new_fields` action on `NodesController`:

```ruby
def new_fields
  render partial: "dashboard/flows/nodes/fields_#{params[:node_type]}", locals: {node: FlowNode.new(flow_id: params[:flow_id]), flow: Flow.find(params[:flow_id])}
end
```

And route: `get "nodes/new.fields", to: "flows/nodes#new_fields"` inside the flow nesting. (If routing format ambiguity gives you trouble, expose it as `get :fields_template, on: :collection`.) Keep it simple — JSON textarea is enough for v1.

- [ ] **Step 5: Light component-level smoke** — visit `/dashboard/flows/:id` as admin in a system spec, click "Add" with `node_type: "menu"`, paste JSON, save — verify the node appears with the right content.

(For v1 acceptance, leave system spec covered by a controller-level request spec from Task 3. UI sugar can be exercised manually.)

- [ ] **Step 6: Commit**

```bash
git add packages/app/app/views/dashboard/flows/ \
        packages/app/app/frontend/controllers/node_type_swap_controller.js \
        packages/app/app/controllers/dashboard/flows/nodes_controller.rb
git commit -m "feat(dashboard): flow node form partials + node_type swap"
```

---

## Task 6: Regression + PROGRESS + Spec 07 Shipped

- [ ] **Step 1: Full suite + standardrb**

Run: `bundle exec rspec && bundle exec standardrb --fix`. Expected: green.

- [ ] **Step 2: Manual smoke**

Login as admin. Visit `/dashboard/flows`. Create a flow. Add a `message` node, a `collect` node, a `menu` node, a `handoff` node. Set the message node as root. Activate the flow on a channel. Trigger inbound via `meta-stub` — verify the bot greets.

- [ ] **Step 3: Update `docs/PROGRESS.md`**

Flip 07d row Draft → In Progress → Shipped on merge. **Flip Spec 07 row to Shipped** since this is the last plan. Add a "Recently shipped" entry summarizing Spec 07.

- [ ] **Step 4: PR + merge + final docs commit**

```bash
git push -u origin plan-07d-flow-management-dashboard
gh pr create --title "Plan 07d: Flow management dashboard" --body-file docs/plans/07d-2026-05-15-flow-management-dashboard.md
gh pr merge --squash --delete-branch
```

After merge: sync main, flip 07d to Shipped + Spec 07 to Shipped, add Recently-shipped entry, commit `docs(progress): Spec 07 fully shipped`, push.

---

Spec 07 complete after this plan. Run `/clear`. Repo is at v1 product completeness: ingestion, dispatch, workspace, flows.
