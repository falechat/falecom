# Plan 06b: Transfer + Resolve / Reopen

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans`.
> **Spec:** [06 — Assignment, Transfer & Workspace](../specs/06-assignment-transfer-workspace.md)
> **Date:** 2026-05-11
> **Status:** Draft — awaiting approval
> **Branch:** `plan-06b-transfer-resolve`
> **Depends on:** Plan 06a (uses `ConversationPolicy`, `AutoAssignJob`)

**Goal:** Implement `Assignments::Transfer` (reassign / team transfer / unassign — including optional system-message note), the transfer modal UI, `POST /dashboard/conversations/:id/transfer`, the resolve action (`POST /dashboard/conversations/:id/resolve`), and the pickup action (`POST /dashboard/conversations/:id/pickup`). After this plan, agents can hand conversations off to teammates or other teams with a single click and resolve them when done; every action emits the canonical event and is policy-gated.

**Architecture:** A single `Assignments::Transfer` service handles all four transfer flavors from Spec §2.5. Authorization is delegated to `ConversationPolicy#can_transfer?` so the policy stays the single source of truth. The note (when present) is written through `Messages::Create` with `direction: "outbound"`, `status: "received"`, `sender: nil` — same convention Spec 04 v2 introduced for system-origin messages, so `ProcessStatusUpdate` and `SendMessageJob` both ignore it. Team-transfer that ends with no assignee enqueues `AutoAssignJob` for the destination team (matches Spec §7 decision). Resolve is a tiny service that sets `status: "resolved"`, emits `conversations:resolved`, and broadcasts. Pickup reuses `Assignments::Transfer` with `to_user: current_user`. Modal UI uses the existing JR Components modal pattern from the dashboard.

**Tech Stack:** Ruby 4.0.2, Rails 8.1.3, Solid Queue, RSpec 7.1, ViewComponent, Hotwire (Turbo Streams + Stimulus for the modal trigger). No new gems.

---

## Files to touch

### Create — services

- `packages/app/app/services/assignments/transfer.rb`
- `packages/app/app/services/conversations/resolve.rb`
- `packages/app/app/components/transfer_modal_component.rb`
- `packages/app/app/components/transfer_modal_component.html.erb`

### Create — controllers / routes

- `packages/app/app/controllers/dashboard/conversations/transfers_controller.rb`
- `packages/app/app/controllers/dashboard/conversations/resolutions_controller.rb`
- `packages/app/app/controllers/dashboard/conversations/pickups_controller.rb`

### Create — specs

- `packages/app/spec/services/assignments/transfer_spec.rb`
- `packages/app/spec/services/conversations/resolve_spec.rb`
- `packages/app/spec/requests/dashboard/conversations/transfers_spec.rb`
- `packages/app/spec/requests/dashboard/conversations/resolutions_spec.rb`
- `packages/app/spec/requests/dashboard/conversations/pickups_spec.rb`
- `packages/app/spec/components/transfer_modal_component_spec.rb`

### Modify

- `packages/app/config/routes.rb` — nest the three resources under `resources :conversations`.
- `packages/app/app/views/dashboard/conversations/show.html.erb` — render Transfer + Resolve + Pickup buttons gated by policy.
- `packages/app/app/errors/fale_com.rb` (or wherever Spec 04 placed `FaleCom::ValidationError`) — confirm `FaleCom::AuthorizationError` exists; if 06a created it, just use it.

---

## Order of operations

1. **`Assignments::Transfer` service** — all four flavors, note system message, authorization, target validation, event emission, post-transfer auto-assign for empty-assignee team transfer.
2. **`Conversations::Resolve` service.**
3. **Routes** (so request specs can reference paths).
4. **Transfers controller + request spec.**
5. **Resolutions controller + request spec.**
6. **Pickups controller + request spec.**
7. **Transfer modal component** + its spec + view wiring.
8. **Regression sweep + PROGRESS.**

---

## What could go wrong

**Most likely:** the note system message bleeds into outbound dispatch because some downstream code keys off `direction: "outbound"`. Mitigation: Spec 04 already stipulates the `sender: nil + status: "received"` combo means "system-origin, don't dispatch"; `SendMessageJob` early-returns for `status != "pending"`. Verify in the Transfer spec with a job-count assertion.

**Least likely:** routes collide with the existing `resources :messages` nested under conversations. Keep the new routes as named member endpoints.

---

## Task 1: `Assignments::Transfer`

**Files:**
- Create: `packages/app/app/services/assignments/transfer.rb`
- Test: `packages/app/spec/services/assignments/transfer_spec.rb`

- [ ] **Step 1: Write failing spec**

```ruby
require "rails_helper"

RSpec.describe Assignments::Transfer do
  include ActiveJob::TestHelper

  let(:team_a)  { create(:team) }
  let(:team_b)  { create(:team) }
  let(:channel) do
    create(:channel, auto_assign: true, auto_assign_config: {"strategy" => "round_robin"}).tap do |c|
      ChannelTeam.create!(channel: c, team: team_a)
      ChannelTeam.create!(channel: c, team: team_b)
    end
  end
  let(:other_channel) { create(:channel) } # not attended by team_b
  let(:user_a)  { create(:user, role: "agent").tap { |u| TeamMember.create!(user: u, team: team_a) } }
  let(:user_b)  { create(:user, role: "agent").tap { |u| TeamMember.create!(user: u, team: team_b) } }
  let(:admin)   { create(:user, role: "admin") }
  let(:conversation) { create(:conversation, channel: channel, team: team_a, assignee: user_a, status: "assigned") }

  describe "reassign (to_user only)" do
    let!(:user_a2) { create(:user, role: "agent").tap { |u| TeamMember.create!(user: u, team: team_a) } }

    it "updates assignee, keeps team, status assigned" do
      described_class.call(conversation: conversation, to_user: user_a2, actor: user_a)
      expect(conversation.reload).to have_attributes(assignee: user_a2, team: team_a, status: "assigned")
    end

    it "emits conversations:transferred with from/to" do
      expect {
        described_class.call(conversation: conversation, to_user: user_a2, actor: user_a)
      }.to change { Event.where(name: "conversations:transferred", subject: conversation).count }.by(1)
    end
  end

  describe "team transfer (to_team only)" do
    it "moves team, clears assignee, status queued, enqueues AutoAssignJob for the new team" do
      expect {
        described_class.call(conversation: conversation, to_team: team_b, actor: admin)
      }.to have_enqueued_job(AutoAssignJob).with(conversation.id)
      expect(conversation.reload).to have_attributes(team: team_b, assignee_id: nil, status: "queued")
    end

    it "rejects target team that doesn't attend the channel" do
      orphan_team = create(:team)
      expect {
        described_class.call(conversation: conversation, to_team: orphan_team, actor: admin)
      }.to raise_error(FaleCom::ValidationError, /does not attend/i)
    end
  end

  describe "team transfer + assign (to_team + to_user)" do
    it "moves and assigns" do
      described_class.call(conversation: conversation, to_team: team_b, to_user: user_b, actor: admin)
      expect(conversation.reload).to have_attributes(team: team_b, assignee: user_b, status: "assigned")
    end

    it "rejects when user is not a member of the target team" do
      expect {
        described_class.call(conversation: conversation, to_team: team_b, to_user: user_a, actor: admin)
      }.to raise_error(FaleCom::ValidationError, /not a member/i)
    end
  end

  describe "unassign (no args)" do
    it "clears assignee, keeps team, status queued, does NOT auto-enqueue" do
      expect {
        described_class.call(conversation: conversation, actor: user_a)
      }.not_to have_enqueued_job(AutoAssignJob)
      expect(conversation.reload).to have_attributes(team: team_a, assignee_id: nil, status: "queued")
    end
  end

  describe "note" do
    it "creates a system message visible in the conversation thread" do
      expect {
        described_class.call(conversation: conversation, to_user: user_a, actor: user_a, note: "FYI customer is angry")
      }.to change { conversation.messages.count }.by(1)
      msg = conversation.messages.order(:created_at).last
      expect(msg).to have_attributes(content: "FYI customer is angry", sender: nil, direction: "outbound", status: "received")
    end

    it "does NOT enqueue SendMessageJob for the system message" do
      expect {
        described_class.call(conversation: conversation, to_user: user_a, actor: user_a, note: "x")
      }.not_to have_enqueued_job(SendMessageJob)
    end
  end

  describe "authorization" do
    it "raises when actor cannot transfer" do
      stranger = create(:user, role: "agent")
      expect {
        described_class.call(conversation: conversation, to_user: user_a, actor: stranger)
      }.to raise_error(FaleCom::AuthorizationError)
    end
  end
end
```

- [ ] **Step 2: Run, verify fail.** Expected: uninitialized constant.

- [ ] **Step 3: Implement**

```ruby
module Assignments
  class Transfer
    def self.call(**kwargs) = new(**kwargs).call

    def initialize(conversation:, to_team: nil, to_user: nil, note: nil, actor:)
      @conversation = conversation
      @to_team = to_team
      @to_user = to_user
      @note = note
      @actor = actor
    end

    def call
      authorize!
      validate_target!

      from_team_id = @conversation.team_id
      from_user_id = @conversation.assignee_id

      target_team = @to_team || (@to_user ? @conversation.team : nil)
      status = @to_user ? "assigned" : "queued"

      ActiveRecord::Base.transaction do
        @conversation.update!(team: target_team, assignee: @to_user, status: status)
        create_note_message if @note.present?
        Events::Emit.call(
          name: "conversations:transferred",
          subject: @conversation,
          actor: @actor,
          payload: {
            from_team_id: from_team_id, to_team_id: target_team&.id,
            from_user_id: from_user_id, to_user_id: @to_user&.id,
            note: @note
          }
        )
      end

      if @to_team && @to_user.nil?
        ActiveRecord::Base.after_all_transactions_committed do
          AutoAssignJob.perform_later(@conversation.id)
        end
      end

      broadcast_transfer(from_user_id, from_team_id)
      @conversation
    end

    private

    def authorize!
      raise FaleCom::AuthorizationError unless ConversationPolicy.new(@actor, @conversation).can_transfer?
    end

    def validate_target!
      if @to_team && !@conversation.channel.teams.exists?(@to_team.id)
        raise FaleCom::ValidationError, "Team does not attend this channel"
      end
      if @to_user && @to_team && !@to_team.users.exists?(@to_user.id)
        raise FaleCom::ValidationError, "User is not a member of the target team"
      end
    end

    def create_note_message
      Messages::Create.call(
        conversation: @conversation,
        direction: "outbound",
        content: @note,
        content_type: "text",
        status: "received",
        sender: nil
      )
    end

    def broadcast_transfer(_from_user_id, _from_team_id)
      # 06f wires the real Turbo Stream targets. Stay decoupled here.
      nil
    end
  end
end
```

- [ ] **Step 4: Verify pass.** Run the spec; all green.

- [ ] **Step 5: Commit**

```bash
git add packages/app/app/services/assignments/transfer.rb \
        packages/app/spec/services/assignments/transfer_spec.rb
git commit -m "feat(assignments): add Transfer service (reassign, team, unassign, note)"
```

---

## Task 2: `Conversations::Resolve`

**Files:**
- Create: `packages/app/app/services/conversations/resolve.rb`
- Test: `packages/app/spec/services/conversations/resolve_spec.rb`

- [ ] **Step 1: Failing spec**

```ruby
require "rails_helper"

RSpec.describe Conversations::Resolve do
  let(:channel) { create(:channel) }
  let(:team)    { create(:team).tap { |t| ChannelTeam.create!(channel: channel, team: t) } }
  let(:user)    { create(:user, role: "agent").tap { |u| TeamMember.create!(user: u, team: team) } }
  let(:conv)    { create(:conversation, channel: channel, team: team, assignee: user, status: "assigned") }

  it "sets status to resolved + emits event when actor can resolve" do
    expect {
      described_class.call(conversation: conv, actor: user)
    }.to change { conv.reload.status }.from("assigned").to("resolved")
      .and change { Event.where(name: "conversations:resolved", subject: conv).count }.by(1)
  end

  it "raises AuthorizationError otherwise" do
    stranger = create(:user, role: "agent")
    expect {
      described_class.call(conversation: conv, actor: stranger)
    }.to raise_error(FaleCom::AuthorizationError)
  end
end
```

- [ ] **Step 2: Run, fail.** Implement:

```ruby
module Conversations
  class Resolve
    def self.call(conversation:, actor:)
      raise FaleCom::AuthorizationError unless ConversationPolicy.new(actor, conversation).can_resolve?
      conversation.update!(status: "resolved")
      Events::Emit.call(name: "conversations:resolved", subject: conversation, actor: actor)
      conversation
    end
  end
end
```

- [ ] **Step 3: Pass + commit**

```bash
git add packages/app/app/services/conversations/resolve.rb \
        packages/app/spec/services/conversations/resolve_spec.rb
git commit -m "feat(conversations): add Resolve service"
```

---

## Task 3: Routes

**Files:**
- Modify: `packages/app/config/routes.rb`

- [ ] **Step 1: Edit**

```ruby
namespace :dashboard do
  resources :conversations, only: [:index, :show] do
    resources :messages, only: [:create]
    resource :transfer, only: [:new, :create], module: :conversations
    resource :resolution, only: [:create], module: :conversations
    resource :pickup, only: [:create], module: :conversations
  end
  patch "users/availability", to: "users#update_availability", as: :user_availability
end
```

- [ ] **Step 2: `bundle exec rails routes | grep conversation`** — verify the six new entries appear.

- [ ] **Step 3: Commit**

```bash
git add packages/app/config/routes.rb
git commit -m "chore(routes): add transfer/resolution/pickup routes for conversations"
```

---

## Task 4: Transfers controller

**Files:**
- Create: `packages/app/app/controllers/dashboard/conversations/transfers_controller.rb`
- Test: `packages/app/spec/requests/dashboard/conversations/transfers_spec.rb`

- [ ] **Step 1: Failing spec**

```ruby
require "rails_helper"

RSpec.describe "Dashboard::Conversations::Transfers", type: :request do
  let(:team_a) { create(:team) }
  let(:team_b) { create(:team) }
  let(:channel) do
    create(:channel).tap do |c|
      ChannelTeam.create!(channel: c, team: team_a)
      ChannelTeam.create!(channel: c, team: team_b)
    end
  end
  let(:agent)   { create(:user, role: "agent").tap { |u| TeamMember.create!(user: u, team: team_a) } }
  let(:agent_b) { create(:user, role: "agent").tap { |u| TeamMember.create!(user: u, team: team_b) } }
  let(:conv) { create(:conversation, channel: channel, team: team_a, assignee: agent, status: "assigned") }

  before { sign_in_as(agent) }

  it "GET new renders the transfer modal" do
    get new_dashboard_conversation_transfer_path(conv)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Transfer")
  end

  it "POST create transfers and redirects" do
    post dashboard_conversation_transfer_path(conv), params: {transfer: {to_team_id: team_b.id, to_user_id: agent_b.id, note: "context"}}
    expect(response).to redirect_to(dashboard_conversation_path(conv))
    expect(conv.reload).to have_attributes(team: team_b, assignee: agent_b)
  end

  it "POST returns 403 when unauthorized" do
    stranger = create(:user, role: "agent")
    sign_in_as(stranger)
    post dashboard_conversation_transfer_path(conv), params: {transfer: {to_user_id: agent_b.id}}
    expect(response).to have_http_status(:forbidden)
  end

  it "POST returns 422 on validation error" do
    orphan_team = create(:team)
    post dashboard_conversation_transfer_path(conv), params: {transfer: {to_team_id: orphan_team.id}}
    expect(response).to have_http_status(:unprocessable_content)
  end
end
```

- [ ] **Step 2: Run, fail.** Implement:

```ruby
module Dashboard
  module Conversations
    class TransfersController < ApplicationController
      before_action :load_conversation

      def new
        render TransferModalComponent.new(conversation: @conversation, actor: Current.user)
      end

      def create
        ::Assignments::Transfer.call(
          conversation: @conversation,
          to_team: lookup(Team, params.dig(:transfer, :to_team_id)),
          to_user: lookup(User, params.dig(:transfer, :to_user_id)),
          note: params.dig(:transfer, :note).presence,
          actor: Current.user
        )
        redirect_to dashboard_conversation_path(@conversation)
      rescue FaleCom::AuthorizationError
        head :forbidden
      rescue FaleCom::ValidationError => e
        render plain: e.message, status: :unprocessable_content
      end

      private

      def load_conversation
        @conversation = ::Conversation.find(params[:conversation_id])
        head :forbidden and return unless ConversationPolicy.new(Current.user, @conversation).can_view?
      end

      def lookup(klass, id) = id.present? ? klass.find(id) : nil
    end
  end
end
```

- [ ] **Step 3: Verify pass + commit**

```bash
git add packages/app/app/controllers/dashboard/conversations/transfers_controller.rb \
        packages/app/spec/requests/dashboard/conversations/transfers_spec.rb
git commit -m "feat(dashboard): TransfersController (new + create)"
```

---

## Task 5: Resolutions controller

**Files:**
- Create: `packages/app/app/controllers/dashboard/conversations/resolutions_controller.rb`
- Test: `packages/app/spec/requests/dashboard/conversations/resolutions_spec.rb`

- [ ] **Step 1: Failing spec**

```ruby
require "rails_helper"

RSpec.describe "Dashboard::Conversations::Resolutions", type: :request do
  let(:team) { create(:team) }
  let(:channel) { create(:channel).tap { |c| ChannelTeam.create!(channel: c, team: team) } }
  let(:agent) { create(:user, role: "agent").tap { |u| TeamMember.create!(user: u, team: team) } }
  let(:conv) { create(:conversation, channel: channel, team: team, assignee: agent, status: "assigned") }

  before { sign_in_as(agent) }

  it "POST resolves the conversation" do
    post dashboard_conversation_resolution_path(conv)
    expect(conv.reload.status).to eq("resolved")
  end

  it "403 when not authorized" do
    sign_in_as(create(:user, role: "agent"))
    post dashboard_conversation_resolution_path(conv)
    expect(response).to have_http_status(:forbidden)
  end
end
```

- [ ] **Step 2: Implement**

```ruby
module Dashboard
  module Conversations
    class ResolutionsController < ApplicationController
      def create
        conv = ::Conversation.find(params[:conversation_id])
        ::Conversations::Resolve.call(conversation: conv, actor: Current.user)
        redirect_to dashboard_conversation_path(conv)
      rescue FaleCom::AuthorizationError
        head :forbidden
      end
    end
  end
end
```

- [ ] **Step 3: Pass + commit**

```bash
git add packages/app/app/controllers/dashboard/conversations/resolutions_controller.rb \
        packages/app/spec/requests/dashboard/conversations/resolutions_spec.rb
git commit -m "feat(dashboard): ResolutionsController"
```

---

## Task 6: Pickups controller

**Files:**
- Create: `packages/app/app/controllers/dashboard/conversations/pickups_controller.rb`
- Test: `packages/app/spec/requests/dashboard/conversations/pickups_spec.rb`

- [ ] **Step 1: Failing spec**

```ruby
require "rails_helper"

RSpec.describe "Dashboard::Conversations::Pickups", type: :request do
  let(:team) { create(:team) }
  let(:channel) { create(:channel).tap { |c| ChannelTeam.create!(channel: c, team: team) } }
  let(:agent) { create(:user, role: "agent", availability: "online").tap { |u| TeamMember.create!(user: u, team: team) } }
  let(:conv) { create(:conversation, channel: channel, team: team, status: "queued", assignee: nil) }

  before { sign_in_as(agent) }

  it "assigns the conversation to current_user" do
    post dashboard_conversation_pickup_path(conv)
    expect(conv.reload).to have_attributes(assignee: agent, status: "assigned")
  end

  it "403 on unaccessible channel" do
    foreign = create(:conversation, status: "queued")
    post dashboard_conversation_pickup_path(foreign)
    expect(response).to have_http_status(:forbidden)
  end
end
```

- [ ] **Step 2: Implement**

```ruby
module Dashboard
  module Conversations
    class PickupsController < ApplicationController
      def create
        conv = ::Conversation.find(params[:conversation_id])
        head :forbidden and return unless ConversationPolicy.new(Current.user, conv).can_pickup?
        ::Assignments::Transfer.call(conversation: conv, to_team: conv.channel.teams.first, to_user: Current.user, actor: Current.user)
        redirect_to dashboard_conversation_path(conv)
      end
    end
  end
end
```

If multiple teams attend the channel, prefer one the picker actually belongs to:

```ruby
team = (conv.channel.teams & Current.user.teams).first || conv.channel.teams.first
```

- [ ] **Step 3: Pass + commit**

```bash
git add packages/app/app/controllers/dashboard/conversations/pickups_controller.rb \
        packages/app/spec/requests/dashboard/conversations/pickups_spec.rb
git commit -m "feat(dashboard): PickupsController for self-assign"
```

---

## Task 7: Transfer modal component + show-view wiring

**Files:**
- Create: `packages/app/app/components/transfer_modal_component.rb`
- Create: `packages/app/app/components/transfer_modal_component.html.erb`
- Test: `packages/app/spec/components/transfer_modal_component_spec.rb`
- Modify: `packages/app/app/views/dashboard/conversations/show.html.erb`

- [ ] **Step 1: Failing component spec**

```ruby
require "rails_helper"

RSpec.describe TransferModalComponent, type: :component do
  let(:team_a) { create(:team, name: "Sales") }
  let(:team_b) { create(:team, name: "Finance") }
  let(:channel) do
    create(:channel).tap do |c|
      ChannelTeam.create!(channel: c, team: team_a)
      ChannelTeam.create!(channel: c, team: team_b)
    end
  end
  let(:user)  { create(:user, role: "agent").tap { |u| TeamMember.create!(user: u, team: team_a) } }
  let(:user2) { create(:user, role: "agent").tap { |u| TeamMember.create!(user: u, team: team_b) } }
  let(:conv)  { create(:conversation, channel: channel) }

  it "renders only teams attending the channel" do
    rendered = render_inline(described_class.new(conversation: conv, actor: user))
    expect(rendered.css("select[name='transfer[to_team_id]'] option").map(&:text)).to include("Sales", "Finance")
  end

  it "renders the note textarea" do
    rendered = render_inline(described_class.new(conversation: conv, actor: user))
    expect(rendered.css("textarea[name='transfer[note]']")).not_to be_empty
  end
end
```

- [ ] **Step 2: Implement**

```ruby
class TransferModalComponent < ViewComponent::Base
  def initialize(conversation:, actor:)
    @conversation = conversation
    @actor = actor
  end

  def teams = @conversation.channel.teams.order(:name)
end
```

```erb
<div class="modal" data-controller="modal" role="dialog">
  <%= form_with url: dashboard_conversation_transfer_path(@conversation), method: :post do |f| %>
    <h2 class="text-lg font-semibold mb-3">Transfer conversation</h2>

    <%= f.label :to_team_id, "Team" %>
    <%= f.select "transfer[to_team_id]", teams.map { |t| [t.name, t.id] }, {include_blank: "— keep current —"}, class: "w-full mb-2",
          data: {action: "change->modal#refreshUsers", "modal-users-url": dashboard_conversation_transfer_path(@conversation, format: :json)} %>

    <%= f.label :to_user_id, "Agent" %>
    <%= f.select "transfer[to_user_id]", [], {include_blank: "— unassigned —"}, class: "w-full mb-2", data: {modal_target: "userSelect"} %>

    <%= f.label :note, "Note (optional)" %>
    <%= f.text_area "transfer[note]", rows: 3, class: "w-full mb-3" %>

    <div class="flex justify-end gap-2">
      <button type="button" data-action="modal#close" class="btn-secondary">Cancel</button>
      <%= f.submit "Transfer", class: "btn-primary" %>
    </div>
  <% end %>
</div>
```

For the user-select refresh, add a JSON branch to the controller's `new` action returning `{users: team.users.map { ... }}` filtered by `to_team_id` query param, and a tiny `modal_controller.js` Stimulus controller that fetches it. Implementation:

```js
// app/javascript/controllers/modal_controller.js
import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets = ["userSelect"]
  async refreshUsers(e) {
    const url = new URL(this.element.querySelector("select[name='transfer[to_team_id]']").dataset.modalUsersUrl, window.location.origin)
    url.searchParams.set("to_team_id", e.target.value)
    const res = await fetch(url, {headers: {Accept: "application/json"}})
    const {users} = await res.json()
    this.userSelectTarget.innerHTML = "<option value=''>— unassigned —</option>" + users.map(u => `<option value="${u.id}">${u.name}</option>`).join("")
  }
  close() { this.element.remove() }
}
```

Update `TransfersController#new` to respond to `format.json`:

```ruby
def new
  if request.format.json?
    team = Team.find(params[:to_team_id])
    render json: {users: team.users.select(:id, :name)}
  else
    render TransferModalComponent.new(conversation: @conversation, actor: Current.user)
  end
end
```

- [ ] **Step 3: Wire into the show view**

In `packages/app/app/views/dashboard/conversations/show.html.erb`, near the conversation header, add:

```erb
<% policy = ConversationPolicy.new(Current.user, @conversation) %>
<div class="flex gap-2">
  <% if policy.can_pickup? %>
    <%= button_to "Pick up", dashboard_conversation_pickup_path(@conversation), method: :post, class: "btn-primary" %>
  <% end %>
  <% if policy.can_transfer? %>
    <%= link_to "Transfer", new_dashboard_conversation_transfer_path(@conversation), data: {turbo_frame: "modal"}, class: "btn-secondary" %>
  <% end %>
  <% if policy.can_resolve? && @conversation.status != "resolved" %>
    <%= button_to "Resolve", dashboard_conversation_resolution_path(@conversation), method: :post, class: "btn-secondary" %>
  <% end %>
</div>
<turbo-frame id="modal"></turbo-frame>
```

- [ ] **Step 4: Verify pass — component spec + show-view smoke**

```bash
bundle exec rspec spec/components/transfer_modal_component_spec.rb
bundle exec rspec spec/requests/dashboard/conversations/
```

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add packages/app/app/components/transfer_modal_component* \
        packages/app/app/javascript/controllers/modal_controller.js \
        packages/app/app/views/dashboard/conversations/show.html.erb \
        packages/app/spec/components/transfer_modal_component_spec.rb
git commit -m "feat(dashboard): transfer modal + pickup/resolve buttons on conversation show"
```

---

## Task 8: Regression sweep + PROGRESS

- [ ] **Step 1: Full suite**

Run: `bundle exec rspec && bin/standardrb --fix`
Expected: all green.

- [ ] **Step 2: Manual smoke**

Login as agent. Pickup a queued conversation. Transfer it to a teammate with a note. Verify the note shows up as a system message in the timeline (will look better once 06d ships, but the row should be there).

- [ ] **Step 3: Update `docs/PROGRESS.md`** — add 06b row, In Progress → Shipped on merge.

- [ ] **Step 4: PR**

```bash
git push -u origin plan-06b-transfer-resolve
gh pr create --title "Plan 06b: Transfer + Resolve" \
             --body-file docs/plans/06b-2026-05-11-transfer-resolve.md
```

---

You can now run `/clear` and `/execute-plan docs/plans/06c-2026-05-11-workspace-views.md`.
