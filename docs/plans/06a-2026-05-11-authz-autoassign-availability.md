# Plan 06a: Authorization + Auto-Assign + Availability

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans`.
> **Spec:** [06 — Assignment, Transfer & Workspace](../specs/06-assignment-transfer-workspace.md)
> **Date:** 2026-05-11
> **Status:** Draft — awaiting approval
> **Branch:** `plan-06a-authz-autoassign-availability`

**Goal:** Ship the foundation of Spec 06: `ConversationPolicy` (authorization for every conversation read/write), `Assignments::AutoAssign` (round-robin + capacity strategies, online-only eligibility, advisory-lock concurrency), `AutoAssignJob` (enqueued, never inline), agent availability toggle (`PATCH /dashboard/users/availability`), and the trigger points that fire auto-assign (new `queued` conversation via `Ingestion::ProcessMessage`; agent goes `online`). After this plan, conversations land in the right agent's lap without anyone clicking anything, agents can flip their availability, and `ConversationPolicy` is the one chokepoint every later plan (06b transfer, 06c workspace, 06f cable) leans on.

**Architecture:** `ConversationPolicy` is a plain Ruby class (no Pundit gem). Constructor takes `(user, conversation)`; methods return booleans. `user_channel_ids` memoized inside the instance. `Assignments::AutoAssign` is a service object called only from `AutoAssignJob`; the service opens a transaction, takes a `pg_advisory_xact_lock(hashtext("auto_assign_team_#{team.id}"))` (same inline-pg pattern Spec 04 v2 used for `display_id`), selects an eligible agent under the lock, updates the conversation, emits `conversations:assigned`, and broadcasts. Availability is a single PATCH endpoint that updates `current_user.availability` and, when transitioning to `online`, enqueues one `AutoAssignJob` per `queued` conversation on accessible channels. Trigger from `Ingestion::ProcessMessage`: after a brand-new conversation is created with `status: "queued"`, call `AutoAssignJob.perform_later(conversation.id)` inside `after_all_transactions_committed` (same pattern as `Dispatch::Outbound` from Plan 05a).

**Tech Stack:** Ruby 4.0.2, Rails 8.1.3, Solid Queue, RSpec 7.1, `standardrb`. No new gems.

---

## Files to touch

All paths relative to repo root. Commands run inside `falecom-workspace-1` (`docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && …"`).

### Create — policy / services / jobs

- `packages/app/app/policies/conversation_policy.rb`
- `packages/app/app/services/assignments/auto_assign.rb`
- `packages/app/app/services/assignments/eligible_agents.rb`
- `packages/app/app/jobs/auto_assign_job.rb`
- `packages/app/app/controllers/dashboard/users_controller.rb`
- `packages/app/app/errors/fale_com/authorization_error.rb` (only if not already defined; check `app/errors/`)

### Create — specs

- `packages/app/spec/policies/conversation_policy_spec.rb`
- `packages/app/spec/services/assignments/auto_assign_spec.rb`
- `packages/app/spec/services/assignments/eligible_agents_spec.rb`
- `packages/app/spec/jobs/auto_assign_job_spec.rb`
- `packages/app/spec/requests/dashboard/users_availability_spec.rb`
- `packages/app/spec/services/ingestion/process_message_auto_assign_spec.rb` (integration — process inbound message → triggers AutoAssignJob)

### Modify

- `packages/app/app/services/ingestion/process_message.rb` — after `Conversations::ResolveOrCreate` returns a brand-new queued conversation, enqueue `AutoAssignJob.perform_later(conversation.id)` via `after_all_transactions_committed`. Must not re-fire on existing conversations.
- `packages/app/config/routes.rb` — add `patch "users/availability", to: "users#update_availability"` inside `namespace :dashboard`.
- `packages/app/app/components/ui/navbar_component.html.erb` (+ `.rb`) — render an availability dropdown when `Current.user.present?`.
- `packages/app/db/seeds.rb` — make sure at least one channel has `auto_assign: true` with `auto_assign_config: {"strategy" => "round_robin"}` so manual dev sanity checks exercise the path.

---

## Order of operations (TDD wave)

1. **`ConversationPolicy`** — pure logic, no DB writes. Test every cell of the role × action matrix from spec §2.1.
2. **`Assignments::EligibleAgents`** — helper that returns the candidate `User` scope (team members with `availability: "online"`). Pure query.
3. **`Assignments::AutoAssign`** — orchestrator, uses `EligibleAgents`, takes advisory lock, updates conversation, emits event, broadcasts (broadcast call kept as a private no-op until 06f wires real channels — but the call site stays).
4. **`AutoAssignJob`** — wraps `AutoAssign.call`. Idempotent (re-running on an already-assigned conversation is a no-op).
5. **Trigger 1 — `Ingestion::ProcessMessage` integration**: enqueue `AutoAssignJob` after committing a new queued conversation.
6. **Availability endpoint + UI** — `Dashboard::UsersController#update_availability`, navbar dropdown, request spec, and the second trigger (`online` → enqueue jobs for `queued` conversations on accessible channels).
7. **Regression sweep** — `bundle exec rspec`, `bin/standardrb --fix`, manual smoke (`rake ingest:mock` with `auto_assign` channel; assert assigned).

Each task ends with a Conventional Commit.

---

## What could go wrong

**Most likely:** race between two concurrent inbound messages on the same team — both jobs read the same "least-recently-assigned" agent and both update. Mitigation: the `pg_advisory_xact_lock(hashtext("auto_assign_team_#{team.id}"))` makes selection + update atomic per team. Cover with a concurrency spec that spawns two threads.

**Least likely:** `Current.user` is not set in the controller when `update_availability` runs (Spec 02 wired it via session callback). If it returns `nil`, the request 401s — already covered by `authenticated` callback in `ApplicationController`. Verify in the spec.

---

## Task 1: `ConversationPolicy`

**Files:**
- Create: `packages/app/app/policies/conversation_policy.rb`
- Test: `packages/app/spec/policies/conversation_policy_spec.rb`

- [ ] **Step 1: Write the failing spec**

```ruby
require "rails_helper"

RSpec.describe ConversationPolicy do
  let(:channel_a) { create(:channel) }
  let(:channel_b) { create(:channel) }
  let(:team)      { create(:team) }
  let(:other_team) { create(:team) }
  before do
    ChannelTeam.create!(channel: channel_a, team: team)
    ChannelTeam.create!(channel: channel_b, team: other_team)
  end

  let(:agent)      { create(:user, role: "agent").tap   { |u| TeamMember.create!(user: u, team: team) } }
  let(:supervisor) { create(:user, role: "supervisor").tap { |u| TeamMember.create!(user: u, team: team) } }
  let(:admin)      { create(:user, role: "admin") }

  let(:my_conv)         { create(:conversation, channel: channel_a, assignee: agent, team: team, status: "assigned") }
  let(:other_conv)      { create(:conversation, channel: channel_a, status: "queued") }
  let(:foreign_conv)    { create(:conversation, channel: channel_b, status: "queued") }

  describe "#can_view?" do
    it("agent sees own channel")     { expect(described_class.new(agent, my_conv).can_view?).to be true }
    it("agent sees teammates")       { expect(described_class.new(agent, other_conv).can_view?).to be true }
    it("agent blind to other team")  { expect(described_class.new(agent, foreign_conv).can_view?).to be false }
    it("admin sees everything")      { expect(described_class.new(admin, foreign_conv).can_view?).to be true }
  end

  describe "#can_reply?" do
    it("only when assigned")         { expect(described_class.new(agent, my_conv).can_reply?).to be true }
    it("not when unassigned")        { expect(described_class.new(agent, other_conv).can_reply?).to be false }
    it("admin still needs assignment") { expect(described_class.new(admin, other_conv).can_reply?).to be false }
  end

  describe "#can_pickup?" do
    it("yes on queued unassigned on accessible channel") { expect(described_class.new(agent, other_conv).can_pickup?).to be true }
    it("no on assigned")  { expect(described_class.new(agent, my_conv).can_pickup?).to be false }
    it("no on foreign")   { expect(described_class.new(agent, foreign_conv).can_pickup?).to be false }
  end

  describe "#can_transfer?" do
    it("agent can transfer own")        { expect(described_class.new(agent, my_conv).can_transfer?).to be true }
    it("agent can pickup-transfer")     { expect(described_class.new(agent, other_conv).can_transfer?).to be true }
    it("supervisor can transfer any viewable") { expect(described_class.new(supervisor, other_conv).can_transfer?).to be true }
    it("admin unrestricted")            { expect(described_class.new(admin, foreign_conv).can_transfer?).to be true }
    it("agent blocked on foreign")      { expect(described_class.new(agent, foreign_conv).can_transfer?).to be false }
  end

  describe "#can_resolve?" do
    it("assignee yes")     { expect(described_class.new(agent, my_conv).can_resolve?).to be true }
    it("non-assignee no")  { expect(described_class.new(agent, other_conv).can_resolve?).to be false }
    it("supervisor yes if viewable") { expect(described_class.new(supervisor, other_conv).can_resolve?).to be true }
    it("admin yes")        { expect(described_class.new(admin, foreign_conv).can_resolve?).to be true }
  end
end
```

- [ ] **Step 2: Run, verify fail**

Run: `bundle exec rspec spec/policies/conversation_policy_spec.rb`
Expected: `NameError: uninitialized constant ConversationPolicy`.

- [ ] **Step 3: Implement**

```ruby
class ConversationPolicy
  attr_reader :user, :conversation

  def initialize(user, conversation)
    @user = user
    @conversation = conversation
  end

  def can_view?
    return true if user.admin?
    user_channel_ids.include?(conversation.channel_id)
  end

  def can_reply?
    can_view? && conversation.assignee_id == user.id
  end

  def can_pickup?
    can_view? && conversation.assignee_id.nil? && conversation.status == "queued"
  end

  def can_transfer?
    return true if user.admin?
    return true if user.supervisor? && can_view?
    return true if can_pickup?
    conversation.assignee_id == user.id && can_view?
  end

  def can_resolve?
    return true if user.admin?
    return true if user.supervisor? && can_view?
    can_reply?
  end

  private

  def user_channel_ids
    @user_channel_ids ||= user.teams
      .joins(:channel_teams)
      .pluck("channel_teams.channel_id")
      .uniq
  end
end
```

- [ ] **Step 4: Verify pass**

Run: `bundle exec rspec spec/policies/conversation_policy_spec.rb`
Expected: all examples green.

- [ ] **Step 5: Commit**

```bash
git add packages/app/app/policies/conversation_policy.rb \
        packages/app/spec/policies/conversation_policy_spec.rb
git commit -m "feat(authz): add ConversationPolicy for conversation access control"
```

---

## Task 2: `Assignments::EligibleAgents`

**Files:**
- Create: `packages/app/app/services/assignments/eligible_agents.rb`
- Test: `packages/app/spec/services/assignments/eligible_agents_spec.rb`

- [ ] **Step 1: Write failing spec**

```ruby
require "rails_helper"

RSpec.describe Assignments::EligibleAgents do
  let(:team)   { create(:team) }
  let!(:on)    { create(:user, role: "agent", availability: "online") .tap { |u| TeamMember.create!(user: u, team: team) } }
  let!(:busy)  { create(:user, role: "agent", availability: "busy")   .tap { |u| TeamMember.create!(user: u, team: team) } }
  let!(:off)   { create(:user, role: "agent", availability: "offline").tap { |u| TeamMember.create!(user: u, team: team) } }
  let!(:other) { create(:user, role: "agent", availability: "online") } # not on team

  it "returns only online members of the team" do
    expect(described_class.call(team)).to contain_exactly(on)
  end
end
```

- [ ] **Step 2: Run, verify fail**

Run: `bundle exec rspec spec/services/assignments/eligible_agents_spec.rb`
Expected: uninitialized constant.

- [ ] **Step 3: Implement**

```ruby
module Assignments
  class EligibleAgents
    def self.call(team)
      User.joins(:team_members)
        .where(team_members: {team_id: team.id})
        .where(availability: "online")
    end
  end
end
```

- [ ] **Step 4: Verify pass**

Run: `bundle exec rspec spec/services/assignments/eligible_agents_spec.rb`
Expected: green.

- [ ] **Step 5: Commit**

```bash
git add packages/app/app/services/assignments/eligible_agents.rb \
        packages/app/spec/services/assignments/eligible_agents_spec.rb
git commit -m "feat(assignments): add EligibleAgents query"
```

---

## Task 3: `Assignments::AutoAssign`

**Files:**
- Create: `packages/app/app/services/assignments/auto_assign.rb`
- Test: `packages/app/spec/services/assignments/auto_assign_spec.rb`

- [ ] **Step 1: Write failing spec**

```ruby
require "rails_helper"

RSpec.describe Assignments::AutoAssign do
  let(:team) { create(:team) }
  let(:channel) do
    create(:channel, auto_assign: true, auto_assign_config: {"strategy" => "round_robin", "team_id" => team.id})
      .tap { |c| ChannelTeam.create!(channel: c, team: team) }
  end
  let!(:agent_a) { create(:user, role: "agent", availability: "online").tap { |u| TeamMember.create!(user: u, team: team) } }
  let!(:agent_b) { create(:user, role: "agent", availability: "online").tap { |u| TeamMember.create!(user: u, team: team) } }
  let(:conversation) { create(:conversation, channel: channel, team: nil, assignee: nil, status: "queued") }

  it "no-ops when channel.auto_assign is false" do
    channel.update!(auto_assign: false)
    described_class.call(conversation)
    expect(conversation.reload.assignee_id).to be_nil
  end

  it "round-robin picks the agent with fewest active assignments" do
    create(:conversation, channel: channel, assignee: agent_a, status: "assigned")
    described_class.call(conversation)
    expect(conversation.reload.assignee).to eq(agent_b)
    expect(conversation.status).to eq("assigned")
    expect(conversation.team).to eq(team)
  end

  it "capacity strategy honors max capacity" do
    channel.update!(auto_assign_config: {"strategy" => "capacity", "capacity" => 1, "team_id" => team.id})
    create(:conversation, channel: channel, assignee: agent_a, status: "assigned")
    described_class.call(conversation)
    expect(conversation.reload.assignee).to eq(agent_b)
  end

  it "stays queued when no agent is online" do
    User.update_all(availability: "offline")
    described_class.call(conversation)
    expect(conversation.reload).to have_attributes(status: "queued", assignee_id: nil)
  end

  it "emits conversations:assigned" do
    expect { described_class.call(conversation) }
      .to change { Event.where(name: "conversations:assigned", subject: conversation).count }.by(1)
  end

  it "is idempotent — already-assigned conversation is not reassigned" do
    conversation.update!(assignee: agent_a, status: "assigned")
    described_class.call(conversation)
    expect(conversation.reload.assignee).to eq(agent_a)
  end
end
```

- [ ] **Step 2: Run, verify fails**

Expected: uninitialized constant.

- [ ] **Step 3: Implement**

```ruby
module Assignments
  class AutoAssign
    def self.call(conversation)
      new(conversation).call
    end

    def initialize(conversation)
      @conversation = conversation
    end

    def call
      return unless @conversation.channel.auto_assign?
      return if @conversation.assignee_id.present?

      team = pick_team
      return unless team

      ActiveRecord::Base.transaction do
        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.send(:sanitize_sql_array,
            ["SELECT pg_advisory_xact_lock(hashtext(?))", "auto_assign_team_#{team.id}"])
        )

        agent = pick_agent(team)
        return unless agent

        @conversation.update!(assignee: agent, team: team, status: "assigned")
        Events::Emit.call(
          name: "conversations:assigned",
          subject: @conversation,
          actor: :system,
          payload: {assignee_id: agent.id, team_id: team.id, strategy: strategy}
        )
      end

      broadcast_assignment
    end

    private

    def config = @conversation.channel.auto_assign_config.to_h
    def strategy = config["strategy"] || "round_robin"

    def pick_team
      if (id = config["team_id"])
        Team.find_by(id: id)
      else
        @conversation.channel.teams.order(:id).first
      end
    end

    def pick_agent(team)
      pool = Assignments::EligibleAgents.call(team)
      case strategy
      when "capacity" then pick_by_capacity(pool, team)
      else pick_round_robin(pool)
      end
    end

    def pick_round_robin(pool)
      pool.left_outer_joins(:assigned_conversations)
        .where(conversations: {status: ["assigned", nil]})
        .group("users.id")
        .order(Arel.sql("COUNT(conversations.id) ASC, MAX(conversations.updated_at) ASC NULLS FIRST"))
        .first
    end

    def pick_by_capacity(pool, _team)
      cap = (config["capacity"] || 10).to_i
      pool.left_outer_joins(:assigned_conversations)
        .where(conversations: {status: ["assigned", nil]})
        .group("users.id")
        .having("COUNT(conversations.id) < ?", cap)
        .order(Arel.sql("COUNT(conversations.id) ASC"))
        .first
    end

    def broadcast_assignment
      # 06f wires the real Turbo Stream targets. Kept as a placeholder so the
      # call site is stable.
      nil
    end
  end
end
```

- [ ] **Step 4: Verify pass**

Expected: all green. If the round-robin spec is flaky on tie-breaking, add a `sleep 0.001` between fixture creates — or better, set `updated_at` explicitly in the factory call. Prefer the latter.

- [ ] **Step 5: Concurrency spec (extra)**

Append to the same spec file:

```ruby
it "serializes concurrent picks via advisory lock" do
  conv2 = create(:conversation, channel: channel, status: "queued")
  ts = [
    Thread.new { ActiveRecord::Base.connection_pool.with_connection { described_class.call(conversation) } },
    Thread.new { ActiveRecord::Base.connection_pool.with_connection { described_class.call(conv2) } }
  ]
  ts.each(&:join)
  assignees = [conversation.reload.assignee, conv2.reload.assignee]
  expect(assignees.compact.uniq.size).to eq(2)  # both got distinct agents
end
```

Run the file; expected green.

- [ ] **Step 6: Commit**

```bash
git add packages/app/app/services/assignments/auto_assign.rb \
        packages/app/spec/services/assignments/auto_assign_spec.rb
git commit -m "feat(assignments): add AutoAssign service with round-robin + capacity strategies"
```

---

## Task 4: `AutoAssignJob`

**Files:**
- Create: `packages/app/app/jobs/auto_assign_job.rb`
- Test: `packages/app/spec/jobs/auto_assign_job_spec.rb`

- [ ] **Step 1: Write failing spec**

```ruby
require "rails_helper"

RSpec.describe AutoAssignJob do
  let(:conversation) { create(:conversation, status: "queued") }

  it "delegates to Assignments::AutoAssign" do
    expect(Assignments::AutoAssign).to receive(:call).with(conversation)
    described_class.perform_now(conversation.id)
  end

  it "discards on RecordNotFound" do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end
end
```

- [ ] **Step 2: Run, verify fail**

Expected: uninitialized constant.

- [ ] **Step 3: Implement**

```ruby
class AutoAssignJob < ApplicationJob
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(conversation_id)
    Assignments::AutoAssign.call(Conversation.find(conversation_id))
  end
end
```

- [ ] **Step 4: Verify pass + commit**

```bash
git add packages/app/app/jobs/auto_assign_job.rb \
        packages/app/spec/jobs/auto_assign_job_spec.rb
git commit -m "feat(jobs): add AutoAssignJob"
```

---

## Task 5: Trigger from `Ingestion::ProcessMessage`

**Files:**
- Modify: `packages/app/app/services/ingestion/process_message.rb`
- Test: `packages/app/spec/services/ingestion/process_message_auto_assign_spec.rb`

- [ ] **Step 1: Read current `process_message.rb`** to find the `Conversations::ResolveOrCreate.call(...)` site. Add a flag (or detect via `previously_new_record?` / a returned `was_created` boolean — Spec 04 implementation likely already returns the conversation; verify which contract exists).

- [ ] **Step 2: Write failing spec**

```ruby
require "rails_helper"

RSpec.describe "Ingestion::ProcessMessage + auto-assign" do
  include ActiveJob::TestHelper

  let(:team) { create(:team) }
  let(:channel) do
    create(:channel, auto_assign: true, auto_assign_config: {"strategy" => "round_robin"})
      .tap { |c| ChannelTeam.create!(channel: c, team: team) }
  end

  it "enqueues AutoAssignJob exactly once for a brand-new queued conversation" do
    payload = build_inbound_payload(channel: channel) # spec/support helper from Spec 04
    expect {
      Ingestion::ProcessMessage.call(payload)
    }.to have_enqueued_job(AutoAssignJob).exactly(:once)
  end

  it "does NOT re-enqueue for an existing open conversation" do
    payload = build_inbound_payload(channel: channel)
    Ingestion::ProcessMessage.call(payload)
    clear_enqueued_jobs
    Ingestion::ProcessMessage.call(payload.merge("external_id" => SecureRandom.hex))
    expect(enqueued_jobs).to be_empty
  end
end
```

- [ ] **Step 3: Run, verify fail**

Expected: zero enqueued jobs.

- [ ] **Step 4: Edit `Ingestion::ProcessMessage`** to detect the conversation was created in this call (compare `conversation.created_at` to a captured `now`, or have `Conversations::ResolveOrCreate` return `[conversation, created]`). Then:

```ruby
if conversation_created && conversation.status == "queued"
  ActiveRecord::Base.after_all_transactions_committed do
    AutoAssignJob.perform_later(conversation.id)
  end
end
```

If `Conversations::ResolveOrCreate` does not already report creation status, modify it to return `[conversation, created]` and update all callers in the same commit.

- [ ] **Step 5: Verify pass + full ingestion suite**

Run: `bundle exec rspec spec/services/ingestion/`
Expected: all green, no regression.

- [ ] **Step 6: Commit**

```bash
git add packages/app/app/services/ingestion/ \
        packages/app/spec/services/ingestion/process_message_auto_assign_spec.rb
git commit -m "feat(ingestion): trigger AutoAssignJob for new queued conversations"
```

---

## Task 6: Availability endpoint + navbar toggle + online-trigger

**Files:**
- Create: `packages/app/app/controllers/dashboard/users_controller.rb`
- Test: `packages/app/spec/requests/dashboard/users_availability_spec.rb`
- Modify: `packages/app/config/routes.rb`
- Modify: `packages/app/app/components/ui/navbar_component.html.erb` + `.rb`

- [ ] **Step 1: Add route**

In `routes.rb` inside `namespace :dashboard`:

```ruby
patch "users/availability", to: "users#update_availability", as: :user_availability
```

- [ ] **Step 2: Write failing request spec**

```ruby
require "rails_helper"

RSpec.describe "PATCH /dashboard/users/availability" do
  include ActiveJob::TestHelper

  let(:team) { create(:team) }
  let(:channel) do
    create(:channel, auto_assign: true, auto_assign_config: {"strategy" => "round_robin"})
      .tap { |c| ChannelTeam.create!(channel: c, team: team) }
  end
  let(:agent) { create(:user, role: "agent", availability: "offline").tap { |u| TeamMember.create!(user: u, team: team) } }
  let!(:queued) { create(:conversation, channel: channel, status: "queued", assignee: nil) }

  before { sign_in_as(agent) } # spec helper from Spec 01

  it "updates availability and emits users:availability_changed" do
    expect {
      patch dashboard_user_availability_path, params: {availability: "online"}
    }.to change { agent.reload.availability }.from("offline").to("online")
      .and change { Event.where(name: "users:availability_changed", subject: agent).count }.by(1)
  end

  it "enqueues AutoAssignJob for each queued conversation on accessible channels when going online" do
    expect {
      patch dashboard_user_availability_path, params: {availability: "online"}
    }.to have_enqueued_job(AutoAssignJob).with(queued.id)
  end

  it "does not enqueue jobs when going offline or busy" do
    agent.update!(availability: "online")
    expect {
      patch dashboard_user_availability_path, params: {availability: "busy"}
    }.not_to have_enqueued_job(AutoAssignJob)
  end

  it "422s on invalid availability" do
    patch dashboard_user_availability_path, params: {availability: "lol"}
    expect(response).to have_http_status(:unprocessable_content)
  end
end
```

- [ ] **Step 3: Run, verify fail**

Expected: routing error / no controller.

- [ ] **Step 4: Implement controller**

```ruby
module Dashboard
  class UsersController < ApplicationController
    def update_availability
      previous = Current.user.availability
      Current.user.update!(availability: params.fetch(:availability))

      Events::Emit.call(
        name: "users:availability_changed",
        subject: Current.user,
        actor: Current.user,
        payload: {from: previous, to: Current.user.availability}
      )

      if Current.user.online? && previous != "online"
        enqueue_pending_assignments
      end

      respond_to do |fmt|
        fmt.turbo_stream { render turbo_stream: turbo_stream.replace("navbar-availability", partial: "dashboard/users/availability", locals: {user: Current.user}) }
        fmt.html { redirect_back fallback_location: root_path }
      end
    rescue ActiveRecord::RecordInvalid => e
      render plain: e.message, status: :unprocessable_content
    end

    private

    def enqueue_pending_assignments
      channel_ids = Current.user.teams.joins(:channel_teams).pluck("channel_teams.channel_id").uniq
      Conversation.where(channel_id: channel_ids, status: "queued", assignee_id: nil).pluck(:id).each do |cid|
        AutoAssignJob.perform_later(cid)
      end
    end
  end
end
```

- [ ] **Step 5: Add navbar dropdown**

In `navbar_component.html.erb`, add (only when `user.present?`):

```erb
<%= form_with url: dashboard_user_availability_path, method: :patch, data: {turbo_frame: "_top"}, class: "inline-block" do |f| %>
  <%= f.select :availability, [["Online","online"],["Busy","busy"],["Offline","offline"]],
        {selected: user.availability}, onchange: "this.form.requestSubmit()", id: "navbar-availability", class: "rounded border px-2 py-1 text-sm" %>
<% end %>
```

Update `navbar_component.rb` to expose `user`.

- [ ] **Step 6: Verify pass**

Run: `bundle exec rspec spec/requests/dashboard/users_availability_spec.rb`
Expected: green.

- [ ] **Step 7: Commit**

```bash
git add packages/app/app/controllers/dashboard/users_controller.rb \
        packages/app/app/components/ui/navbar_component* \
        packages/app/config/routes.rb \
        packages/app/spec/requests/dashboard/users_availability_spec.rb
git commit -m "feat(dashboard): agent availability toggle + online-triggered AutoAssign"
```

---

## Task 7: Regression sweep + PROGRESS

- [ ] **Step 1: Full rspec**

Run: `docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && bundle exec rspec"`
Expected: all green.

- [ ] **Step 2: standardrb**

Run: `bin/standardrb --fix`
Expected: clean.

- [ ] **Step 3: Manual smoke**

Boot the dashboard. Login as `agent@dev.local` (seed user). Flip availability to "Online". Trigger an inbound message via `rake ingest:mock` on an `auto_assign: true` channel. Verify the conversation row appears with the agent as assignee.

- [ ] **Step 4: Update `docs/PROGRESS.md`**

Flip Spec 06 row from **Draft** → **In Progress**. Add row 06a with status **In Progress** (then **Shipped** after merge).

- [ ] **Step 5: Commit + PR**

```bash
git add docs/PROGRESS.md
git commit -m "docs(progress): Plan 06a in progress"
git push -u origin plan-06a-authz-autoassign-availability
gh pr create --title "Plan 06a: Authorization + Auto-Assign + Availability" \
             --body-file docs/plans/06a-2026-05-11-authz-autoassign-availability.md
```

After merge, flip 06a row to **Shipped** in a follow-up doc commit.

---

You can now run `/clear` and `/execute-plan docs/plans/06b-2026-05-11-transfer-resolve.md`.
