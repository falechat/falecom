# Plan 06c: Workspace Views + Conversation List + Three-Pane Layout

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans`.
> **Spec:** [06 — Assignment, Transfer & Workspace](../specs/06-assignment-transfer-workspace.md)
> **Date:** 2026-05-11
> **Status:** Draft — awaiting approval
> **Branch:** `plan-06c-workspace-views`
> **Depends on:** Plan 06a (uses `ConversationPolicy`).

**Goal:** Turn `/dashboard/conversations` into a real workspace: filtered views (`?view=mine|unassigned|team|channel|all`) scoped by `ConversationPolicy`, a `ConversationListComponent` rendering high-density rows, and a three-pane layout (list | active conversation | contact sidebar) using fixed-height columns. Pagination via Turbo Frame lazy load. After this plan, an agent landing on `/dashboard` sees a workspace, can switch views, and the layout doesn't scroll the page.

**Architecture:** A `Conversations::Scope` query object encapsulates view + access scoping; the controller is thin. The list is a Turbo Frame so view-switching does not full-page-reload. The three-pane layout is a single ERB layout with three flex columns; the center pane renders either an "empty state" or a nested Turbo Frame containing the active conversation's show view. The right pane (contact context) is a partial driven by `@conversation&.contact`. Pagination via simple offset (`?page=N`, 25 per page) — Pagy can come later; for v1, a hand-rolled prev/next link is enough.

**Tech Stack:** Ruby 4.0.2, Rails 8.1.3, ViewComponent, Hotwire (Turbo Frames), Tailwind CSS 4. No new gems.

---

## Files to touch

### Create

- `packages/app/app/services/conversations/scope.rb`
- `packages/app/app/components/conversation_list_component.rb`
- `packages/app/app/components/conversation_list_component.html.erb`
- `packages/app/app/components/conversation_list_row_component.rb`
- `packages/app/app/components/conversation_list_row_component.html.erb`
- `packages/app/app/components/workspace_layout_component.rb`
- `packages/app/app/components/workspace_layout_component.html.erb`
- `packages/app/app/components/contact_sidebar_component.rb`
- `packages/app/app/components/contact_sidebar_component.html.erb`

### Modify

- `packages/app/app/controllers/dashboard/conversations_controller.rb` — replace whatever index/show currently does with the workspace flow.
- `packages/app/app/views/dashboard/conversations/index.html.erb` — render `WorkspaceLayoutComponent`.
- `packages/app/app/views/dashboard/conversations/show.html.erb` — keep the conversation detail but expect it to render inside the center pane of the layout.
- `packages/app/app/views/layouts/application.html.erb` — make sure the dashboard root container is `h-screen overflow-hidden` so the layout fills the viewport.

### Tests

- `packages/app/spec/services/conversations/scope_spec.rb`
- `packages/app/spec/requests/dashboard/conversations_workspace_spec.rb`
- `packages/app/spec/components/conversation_list_row_component_spec.rb`
- `packages/app/spec/components/workspace_layout_component_spec.rb`

---

## Order of operations

1. **`Conversations::Scope`** — pure query class, takes `(user, params)`, returns an `ActiveRecord::Relation`. Test the matrix of views × roles.
2. **`ConversationListRowComponent`** — one row, all visual variants.
3. **`ConversationListComponent`** — wraps the relation in a frame, renders rows + pagination.
4. **`WorkspaceLayoutComponent`** — three-pane skeleton, slots for `list`, `main`, `sidebar`.
5. **`ContactSidebarComponent`** — right pane.
6. **Controller wiring** — `index` renders the layout with all panes; `show` renders the layout with the conversation in the center pane.
7. **Request spec** — exercises view filters end-to-end.
8. **Regression + PROGRESS.**

---

## What could go wrong

**Most likely:** N+1 queries on the list (channel, contact, assignee, last message). Mitigation: `Conversations::Scope` always returns the relation with `.includes(:channel, :contact, :assignee, :team).preload(:messages)` — but for `messages`, only the last one is needed; use a `latest_message` association via `has_one -> { order(created_at: :desc) }`.

**Least likely:** the three-pane CSS over-scrolls because the parent `body` is not full-height. Mitigation: explicit `html, body { height: 100% }` in the global stylesheet (verify it's there from Spec 01).

---

## Task 1: `Conversations::Scope`

**Files:**
- Create: `packages/app/app/services/conversations/scope.rb`
- Test: `packages/app/spec/services/conversations/scope_spec.rb`

- [ ] **Step 1: Failing spec**

```ruby
require "rails_helper"

RSpec.describe Conversations::Scope do
  let(:team_a) { create(:team) }
  let(:team_b) { create(:team) }
  let(:channel_a) { create(:channel).tap { |c| ChannelTeam.create!(channel: c, team: team_a) } }
  let(:channel_b) { create(:channel).tap { |c| ChannelTeam.create!(channel: c, team: team_b) } }
  let(:agent) { create(:user, role: "agent").tap { |u| TeamMember.create!(user: u, team: team_a) } }
  let(:admin) { create(:user, role: "admin") }

  let!(:mine)       { create(:conversation, channel: channel_a, assignee: agent, status: "assigned") }
  let!(:unassigned) { create(:conversation, channel: channel_a, assignee: nil, status: "queued") }
  let!(:teammates)  { create(:conversation, channel: channel_a, team: team_a, status: "assigned") }
  let!(:foreign)    { create(:conversation, channel: channel_b, status: "queued") }

  it "view=mine returns only assigned-to-me" do
    expect(described_class.call(user: agent, params: {view: "mine"})).to contain_exactly(mine)
  end

  it "view=unassigned returns queued+unassigned on accessible channels" do
    expect(described_class.call(user: agent, params: {view: "unassigned"})).to contain_exactly(unassigned)
  end

  it "view=team returns conversations on agent's teams" do
    expect(described_class.call(user: agent, params: {view: "team"})).to contain_exactly(mine, unassigned, teammates)
  end

  it "view=channel filters by channel_id" do
    expect(described_class.call(user: agent, params: {view: "channel", channel_id: channel_a.id})).to contain_exactly(mine, unassigned, teammates)
  end

  it "agent cannot see conversations on inaccessible channels under any view" do
    expect(described_class.call(user: agent, params: {view: "team"})).not_to include(foreign)
  end

  it "view=all is admin-only" do
    expect(described_class.call(user: admin, params: {view: "all"})).to include(mine, unassigned, foreign)
    expect(described_class.call(user: agent, params: {view: "all"})).not_to include(foreign)
  end

  it "orders by last_activity_at desc, nulls last" do
    teammates.update!(last_activity_at: 1.hour.ago)
    mine.update!(last_activity_at: Time.current)
    result = described_class.call(user: agent, params: {view: "team"}).to_a
    expect(result.first).to eq(mine)
  end
end
```

- [ ] **Step 2: Run, fail. Implement:**

```ruby
module Conversations
  class Scope
    def self.call(user:, params:) = new(user: user, params: params).call

    def initialize(user:, params:)
      @user = user
      @params = params
    end

    def call
      base = view_scope.merge(access_scope)
      base.order(Arel.sql("last_activity_at DESC NULLS LAST, created_at DESC"))
        .includes(:channel, :contact, :assignee, :team)
    end

    private

    def view_scope
      case @params[:view].to_s
      when "unassigned" then ::Conversation.where(assignee_id: nil, status: "queued")
      when "team"       then ::Conversation.where(team_id: user_team_ids)
      when "channel"    then ::Conversation.where(channel_id: @params[:channel_id])
      when "all"        then ::Conversation.all
      else                   ::Conversation.where(assignee_id: @user.id) # mine
      end
    end

    def access_scope
      return ::Conversation.all if @user.admin?
      ::Conversation.where(channel_id: user_channel_ids)
    end

    def user_team_ids = @user_team_ids ||= @user.teams.pluck(:id)
    def user_channel_ids
      @user_channel_ids ||= @user.teams.joins(:channel_teams).pluck("channel_teams.channel_id").uniq
    end
  end
end
```

- [ ] **Step 3: Pass + commit**

```bash
git add packages/app/app/services/conversations/scope.rb \
        packages/app/spec/services/conversations/scope_spec.rb
git commit -m "feat(conversations): add Scope query for workspace views"
```

---

## Task 2: `ConversationListRowComponent`

**Files:**
- Create: `packages/app/app/components/conversation_list_row_component.rb`
- Create: `packages/app/app/components/conversation_list_row_component.html.erb`
- Test: `packages/app/spec/components/conversation_list_row_component_spec.rb`

- [ ] **Step 1: Failing spec**

```ruby
require "rails_helper"

RSpec.describe ConversationListRowComponent, type: :component do
  let(:contact) { create(:contact, name: "Maria Silva") }
  let(:channel) { create(:channel, channel_type: "whatsapp_cloud", name: "WhatsApp BR") }
  let(:assignee) { create(:user, name: "Pedro") }
  let(:conv) { create(:conversation, channel: channel, contact: contact, assignee: assignee, status: "assigned", last_activity_at: 5.minutes.ago) }
  let!(:last_msg) { create(:message, conversation: conv, content: "ok, sending now", direction: "outbound", created_at: 5.minutes.ago) }

  it "renders contact name, last message preview, time, status badge" do
    html = render_inline(described_class.new(conversation: conv, active: false))
    expect(html.text).to include("Maria Silva")
    expect(html.text).to include("ok, sending now")
    expect(html.css(".status-badge.assigned")).not_to be_empty
  end

  it "marks active state visually" do
    html = render_inline(described_class.new(conversation: conv, active: true))
    expect(html.css(".row-active")).not_to be_empty
  end

  it "uses bold text when conversation has activity since the agent's last view" do
    # last_activity_at > conv.updated_at OR a per-user read-tracking flag — Spec §7 says bold for unread.
    # For v1 we approximate: bold when last inbound message is newer than last_seen_at on the assignee's session.
    # Pass `unread: true` to the component to render the styling.
    html = render_inline(described_class.new(conversation: conv, active: false, unread: true))
    expect(html.css(".row-unread")).not_to be_empty
  end
end
```

- [ ] **Step 2: Implement**

```ruby
class ConversationListRowComponent < ViewComponent::Base
  def initialize(conversation:, active: false, unread: false)
    @conversation = conversation
    @active = active
    @unread = unread
  end

  def preview = @conversation.messages.order(created_at: :desc).first&.content.to_s.truncate(60)
  def time_ago = @conversation.last_activity_at ? helpers.time_ago_in_words(@conversation.last_activity_at) + " ago" : "—"
  def status = @conversation.status
end
```

```erb
<%= link_to dashboard_conversation_path(@conversation),
      class: "block px-3 py-2 border-b hover:bg-gray-50 #{ "row-active bg-blue-50" if @active } #{ "row-unread font-semibold" if @unread }",
      data: {turbo_frame: "active-conversation"} do %>
  <div class="flex justify-between items-baseline">
    <div class="font-medium truncate"><%= @conversation.contact&.name || "Unknown" %></div>
    <div class="text-xs text-gray-500"><%= time_ago %></div>
  </div>
  <div class="text-sm text-gray-600 truncate"><%= preview %></div>
  <div class="flex gap-2 mt-1 items-center">
    <span class="status-badge <%= status %> inline-block w-2 h-2 rounded-full <%=
      {"bot" => "bg-blue-500", "queued" => "bg-yellow-500", "assigned" => "bg-green-500", "resolved" => "bg-gray-400"}[status] %>"></span>
    <span class="text-xs text-gray-500"><%= @conversation.channel.name %></span>
    <% if @conversation.assignee %>
      <span class="text-xs text-gray-500 ml-auto"><%= @conversation.assignee.name %></span>
    <% end %>
  </div>
<% end %>
```

- [ ] **Step 3: Pass + commit**

```bash
git add packages/app/app/components/conversation_list_row_component* \
        packages/app/spec/components/conversation_list_row_component_spec.rb
git commit -m "feat(components): ConversationListRowComponent"
```

---

## Task 3: `ConversationListComponent`

**Files:**
- Create: `packages/app/app/components/conversation_list_component.rb`
- Create: `packages/app/app/components/conversation_list_component.html.erb`

- [ ] **Step 1: Implement (no separate spec — covered by the request spec in Task 6)**

```ruby
class ConversationListComponent < ViewComponent::Base
  PAGE_SIZE = 25

  def initialize(conversations:, active_id: nil, view: "mine", page: 1)
    @conversations = conversations
    @active_id = active_id
    @view = view
    @page = [page.to_i, 1].max
  end

  def paged = @conversations.offset((@page - 1) * PAGE_SIZE).limit(PAGE_SIZE)
  def total = @conversations.count
  def total_pages = (total / PAGE_SIZE.to_f).ceil
end
```

```erb
<turbo-frame id="conversation-list" class="flex flex-col h-full">
  <header class="p-2 border-b bg-white">
    <nav class="flex gap-1 text-sm">
      <% %w[mine unassigned team].each do |v| %>
        <%= link_to v.titleize, dashboard_conversations_path(view: v),
              class: "px-2 py-1 rounded #{ "bg-blue-100 font-semibold" if @view == v }",
              data: {turbo_frame: "conversation-list"} %>
      <% end %>
    </nav>
  </header>
  <div class="flex-1 overflow-y-auto">
    <% paged.each do |c| %>
      <%= render ConversationListRowComponent.new(conversation: c, active: c.id == @active_id) %>
    <% end %>
  </div>
  <footer class="p-2 border-t bg-white text-xs flex justify-between">
    <span><%= total %> conversations</span>
    <span>
      <% if @page > 1 %>
        <%= link_to "← Prev", dashboard_conversations_path(view: @view, page: @page - 1), data: {turbo_frame: "conversation-list"} %>
      <% end %>
      <% if @page < total_pages %>
        <%= link_to "Next →", dashboard_conversations_path(view: @view, page: @page + 1), data: {turbo_frame: "conversation-list"} %>
      <% end %>
    </span>
  </footer>
</turbo-frame>
```

- [ ] **Step 2: Commit**

```bash
git add packages/app/app/components/conversation_list_component*
git commit -m "feat(components): ConversationListComponent with paging + view tabs"
```

---

## Task 4: `WorkspaceLayoutComponent`

**Files:**
- Create: `packages/app/app/components/workspace_layout_component.rb`
- Create: `packages/app/app/components/workspace_layout_component.html.erb`
- Test: `packages/app/spec/components/workspace_layout_component_spec.rb`

- [ ] **Step 1: Spec (light — just slot rendering)**

```ruby
require "rails_helper"
RSpec.describe WorkspaceLayoutComponent, type: :component do
  it "renders the three slots" do
    html = render_inline(described_class.new) do |c|
      c.with_list { "LIST" }
      c.with_main { "MAIN" }
      c.with_sidebar { "SIDEBAR" }
    end
    expect(html.text).to include("LIST", "MAIN", "SIDEBAR")
  end
end
```

- [ ] **Step 2: Implement**

```ruby
class WorkspaceLayoutComponent < ViewComponent::Base
  renders_one :list
  renders_one :main
  renders_one :sidebar
end
```

```erb
<div class="flex h-screen overflow-hidden">
  <aside class="w-1/4 border-r bg-gray-50"><%= list %></aside>
  <section class="flex-1 flex flex-col"><%= main %></section>
  <aside class="w-1/4 border-l bg-gray-50 overflow-y-auto"><%= sidebar %></aside>
</div>
```

- [ ] **Step 3: Pass + commit**

```bash
git add packages/app/app/components/workspace_layout_component* \
        packages/app/spec/components/workspace_layout_component_spec.rb
git commit -m "feat(components): WorkspaceLayoutComponent (three-pane shell)"
```

---

## Task 5: `ContactSidebarComponent`

**Files:**
- Create: `packages/app/app/components/contact_sidebar_component.rb`
- Create: `packages/app/app/components/contact_sidebar_component.html.erb`

- [ ] **Step 1: Implement**

```ruby
class ContactSidebarComponent < ViewComponent::Base
  def initialize(contact: nil, current_conversation: nil)
    @contact = contact
    @current = current_conversation
  end

  def attributes_pairs = (@contact&.additional_attributes || {}).to_a
  def history
    return [] if @contact.nil?
    ::Conversation.where(contact_id: @contact.id).where.not(id: @current&.id).order(created_at: :desc).limit(20)
  end
end
```

```erb
<% if @contact.nil? %>
  <div class="p-4 text-gray-500 text-sm">Select a conversation to see contact details.</div>
<% else %>
  <div class="p-4 border-b">
    <div class="text-lg font-semibold"><%= @contact.name || "Unknown" %></div>
    <% if @contact.phone_number %><div class="text-sm text-gray-600"><%= @contact.phone_number %></div><% end %>
    <% if @contact.email %><div class="text-sm text-gray-600"><%= @contact.email %></div><% end %>
  </div>

  <% if attributes_pairs.any? %>
    <div class="p-4 border-b">
      <h3 class="text-xs font-semibold uppercase text-gray-500 mb-2">Attributes</h3>
      <dl class="text-sm">
        <% attributes_pairs.each do |k, v| %>
          <div class="flex justify-between py-1">
            <dt class="text-gray-600"><%= k %></dt>
            <dd>
              <% if v.to_s.start_with?("http") %>
                <%= link_to v, v, target: "_blank", class: "text-blue-600 underline" %>
              <% else %>
                <%= v %>
              <% end %>
            </dd>
          </div>
        <% end %>
      </dl>
    </div>
  <% end %>

  <div class="p-4">
    <h3 class="text-xs font-semibold uppercase text-gray-500 mb-2">History</h3>
    <ul class="text-sm space-y-1">
      <% history.each do |c| %>
        <li><%= link_to "##{c.display_id} · #{c.status}", dashboard_conversation_path(c), data: {turbo_frame: "active-conversation"} %></li>
      <% end %>
    </ul>
  </div>
<% end %>
```

- [ ] **Step 2: Commit**

```bash
git add packages/app/app/components/contact_sidebar_component*
git commit -m "feat(components): ContactSidebarComponent"
```

---

## Task 6: Controller wiring + workspace request spec

**Files:**
- Modify: `packages/app/app/controllers/dashboard/conversations_controller.rb`
- Modify: `packages/app/app/views/dashboard/conversations/index.html.erb`
- Modify: `packages/app/app/views/dashboard/conversations/show.html.erb`
- Test: `packages/app/spec/requests/dashboard/conversations_workspace_spec.rb`

- [ ] **Step 1: Failing spec**

```ruby
require "rails_helper"

RSpec.describe "Dashboard workspace", type: :request do
  let(:team) { create(:team) }
  let(:channel_a) { create(:channel).tap { |c| ChannelTeam.create!(channel: c, team: team) } }
  let(:channel_b) { create(:channel) } # not in team
  let(:agent) { create(:user, role: "agent").tap { |u| TeamMember.create!(user: u, team: team) } }
  let!(:mine)    { create(:conversation, channel: channel_a, assignee: agent, status: "assigned") }
  let!(:queued)  { create(:conversation, channel: channel_a, status: "queued") }
  let!(:foreign) { create(:conversation, channel: channel_b, status: "queued") }

  before { sign_in_as(agent) }

  it "GET /dashboard/conversations?view=mine returns only mine" do
    get dashboard_conversations_path(view: "mine")
    expect(response.body).to include("##{mine.display_id}")
    expect(response.body).not_to include("##{queued.display_id}")
  end

  it "view=unassigned excludes foreign channels" do
    get dashboard_conversations_path(view: "unassigned")
    expect(response.body).to include("##{queued.display_id}")
    expect(response.body).not_to include("##{foreign.display_id}")
  end

  it "show renders inside the workspace layout" do
    get dashboard_conversation_path(mine)
    expect(response.body).to include("active-conversation") # turbo-frame id
  end

  it "404s when an agent tries to view a foreign conversation directly" do
    get dashboard_conversation_path(foreign)
    expect(response).to have_http_status(:forbidden)
  end
end
```

- [ ] **Step 2: Implement controller**

```ruby
module Dashboard
  class ConversationsController < ApplicationController
    def index
      @view = params[:view].presence || "mine"
      @page = params[:page].to_i
      @scope = Conversations::Scope.call(user: Current.user, params: {view: @view, channel_id: params[:channel_id]})
      @active = nil
      @contact = nil
    end

    def show
      @conversation = Conversation.find(params[:id])
      head :forbidden and return unless ConversationPolicy.new(Current.user, @conversation).can_view?
      @view = params[:view].presence || "mine"
      @scope = Conversations::Scope.call(user: Current.user, params: {view: @view, channel_id: params[:channel_id]})
      @active = @conversation
      @contact = @conversation.contact
    end
  end
end
```

- [ ] **Step 3: Index view**

`packages/app/app/views/dashboard/conversations/index.html.erb`:

```erb
<%= render WorkspaceLayoutComponent.new do |layout| %>
  <% layout.with_list do %>
    <%= render ConversationListComponent.new(conversations: @scope, view: @view, page: @page) %>
  <% end %>
  <% layout.with_main do %>
    <turbo-frame id="active-conversation" class="flex-1 flex items-center justify-center text-gray-500">
      Select a conversation to begin.
    </turbo-frame>
  <% end %>
  <% layout.with_sidebar do %>
    <%= render ContactSidebarComponent.new %>
  <% end %>
<% end %>
```

- [ ] **Step 4: Show view**

`packages/app/app/views/dashboard/conversations/show.html.erb` becomes:

```erb
<%= render WorkspaceLayoutComponent.new do |layout| %>
  <% layout.with_list do %>
    <%= render ConversationListComponent.new(conversations: @scope, active_id: @conversation.id, view: @view) %>
  <% end %>
  <% layout.with_main do %>
    <turbo-frame id="active-conversation" class="flex-1 flex flex-col">
      <%= render "conversation_detail", conversation: @conversation %>
    </turbo-frame>
  <% end %>
  <% layout.with_sidebar do %>
    <%= render ContactSidebarComponent.new(contact: @contact, current_conversation: @conversation) %>
  <% end %>
<% end %>
```

Move the existing detail markup (header, timeline placeholder, reply form, action buttons from 06b) into a partial `_conversation_detail.html.erb`. The timeline itself is shipped in Plan 06d; for now it renders the old messages list verbatim.

- [ ] **Step 5: Verify pass**

Run: `bundle exec rspec spec/requests/dashboard/conversations_workspace_spec.rb`
Expected: green.

- [ ] **Step 6: Commit**

```bash
git add packages/app/app/controllers/dashboard/conversations_controller.rb \
        packages/app/app/views/dashboard/conversations/ \
        packages/app/spec/requests/dashboard/conversations_workspace_spec.rb
git commit -m "feat(dashboard): workspace views + three-pane layout"
```

---

## Task 7: Regression + PROGRESS

- [ ] **Step 1: Full suite + standardrb**

Run: `bundle exec rspec && bin/standardrb --fix`
Expected: green.

- [ ] **Step 2: Manual smoke**

Boot the dashboard. Verify: three panes, view tabs swap the list (Turbo Frame, no full reload), clicking a row populates the center pane and right sidebar without reloading the page.

- [ ] **Step 3: Update `docs/PROGRESS.md`** — add row 06c.

- [ ] **Step 4: PR**

```bash
git push -u origin plan-06c-workspace-views
gh pr create --title "Plan 06c: Workspace views + 3-pane layout" \
             --body-file docs/plans/06c-2026-05-11-workspace-views.md
```

---

You can now run `/clear` and `/execute-plan docs/plans/06d-2026-05-11-conversation-timeline.md`.
