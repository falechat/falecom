# Plan 07c: Flow Ingestion Integration + Auto-Assign Depth

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans`.
> **Spec:** [07 — Flow Engine](../specs/07-flow-engine.md)
> **Date:** 2026-05-15
> **Status:** Draft — awaiting approval
> **Branch:** `plan-07c-flow-ingestion-integration`
> **Depends on:** Plan 07a (models) + 07b (engine services).

**Goal:** Wire the flow engine into `Ingestion::ProcessMessage` so inbound messages on `bot` conversations run through `Flows::Start` / `Flows::Advance`. Add the `depth` parameter to `AutoAssignJob` (max 3 to break loops). Suppress the new-queued-conversation `AutoAssignJob` enqueue when the channel has an active flow (the bot will hand off when it's ready). End the plan with an end-to-end integration spec: contact sends "Oi" → bot greets → name collected → menu sent → "1" selected → handoff → conversation queued on Vendas team → auto-assign hits.

**Architecture:** A single conditional block in `Ingestion::ProcessMessage` after `Messages::Create` decides whether to start or advance the flow. Decision tree:

1. If `conversation.status != "bot"` → do nothing (flow not active).
2. If `conversation.channel.active_flow_id.nil?` → do nothing (no flow configured).
3. If `conversation.conversation_flow.nil?` → `Flows::Start.call(conversation)`.
4. Else → `Flows::Advance.call(conversation, message)`.

Plan 06a's `ProcessMessage` enqueues `AutoAssignJob` for any new queued conversation. With flows, new conversations on a flow-enabled channel start in `bot` status (set by `Conversations::ResolveOrCreate` when the channel has an active flow) — so they bypass auto-assign at creation. The handoff path in `Flows::Handoff` (already enqueues `AutoAssignJob` if `channel.auto_assign?`) takes over. `AutoAssignJob.perform(conversation_id, depth: 0)` becomes the canonical signature; depth bumps on retry; depth > 3 aborts to prevent assign/transfer/auto-assign infinite loops.

**Tech Stack:** Ruby 4.0.2, Rails 8.1.3, RSpec 7.1, `standardrb`. No new gems.

---

## Files to touch

### Modify

- `packages/app/app/services/ingestion/process_message.rb` — insert flow-engine hook after `Messages::Create`.
- `packages/app/app/services/conversations/resolve_or_create.rb` — on create, set status to `"bot"` when `channel.active_flow_id.present?`, else `"queued"` (current behavior).
- `packages/app/app/jobs/auto_assign_job.rb` — add `depth: 0` keyword arg; abort + log when `depth > 3`.
- `packages/app/app/services/assignments/auto_assign.rb` — accept a `depth:` parameter passed through; do not increment internally (only call sites that re-trigger increment).
- `packages/app/app/services/flows/handoff.rb` (from 07b) — update the `AutoAssignJob.perform_later` call to pass `depth: 0`.

### Create — specs

- `packages/app/spec/services/ingestion/process_message_flow_spec.rb` — covers the four branches above + the end-to-end bot cycle.
- `packages/app/spec/jobs/auto_assign_job_depth_spec.rb` — covers the depth guard.

---

## Order of operations

1. **`AutoAssignJob` depth parameter** — adjust signature + guard. Update existing specs that call it.
2. **`Conversations::ResolveOrCreate` initial status** — set `bot` when flow active.
3. **`Ingestion::ProcessMessage` integration** — call Start/Advance.
4. **`Flows::Handoff` AutoAssign call site** — pass `depth: 0`.
5. **End-to-end integration spec.**
6. **Regression + PROGRESS.**

---

## What could go wrong

**Most likely:** an existing spec (Plan 06a's `process_message_auto_assign_spec.rb`) expects new conversations to enqueue `AutoAssignJob`. After this plan, channels with `active_flow_id` should NOT enqueue at creation. Update that spec to use a channel WITHOUT an active flow, and add a new spec covering the bot path.

**Least likely:** `Conversations::ResolveOrCreate` already sets status from the payload. Read it before patching — the change is "if creating AND channel.active_flow_id.present? AND payload doesn't already specify queued/assigned → status = 'bot'". Default Spec 04 behavior is to start at `bot`; with no flow it should be `queued` (so an agent picks it up directly). Verify Spec 02 / Spec 04 set the column default to `"bot"` — schema shows `default: "bot"`. The change is: when creating AND `channel.active_flow_id.nil?`, override status to `"queued"`. Don't touch existing-conversation reopen paths.

---

## Task 1: `AutoAssignJob` depth parameter

**Files:**
- Modify: `packages/app/app/jobs/auto_assign_job.rb`
- Modify: `packages/app/app/services/assignments/auto_assign.rb` (optional; depth is just propagated to job — service doesn't need it unless it re-enqueues)
- Test: `packages/app/spec/jobs/auto_assign_job_depth_spec.rb`

- [ ] **Step 1: Failing spec**

```ruby
require "rails_helper"
RSpec.describe AutoAssignJob do
  let(:conv) { Conversation.create!(channel: Channel.create!(name: "c", channel_type: "whatsapp_cloud", identifier: "c-1"), contact: Contact.create!, contact_channel: ContactChannel.create!(channel: Channel.last, contact: Contact.last, source_id: "s"), display_id: 1, status: "queued") }

  it "aborts silently when depth > 3" do
    expect(Assignments::AutoAssign).not_to receive(:call)
    described_class.perform_now(conv.id, depth: 4)
  end

  it "calls AutoAssign with depth: 0 by default" do
    expect(Assignments::AutoAssign).to receive(:call).with(conv)
    described_class.perform_now(conv.id)
  end

  it "passes through depth ≤ 3" do
    expect(Assignments::AutoAssign).to receive(:call).with(conv)
    described_class.perform_now(conv.id, depth: 2)
  end
end
```

- [ ] **Step 2: Implement**

```ruby
class AutoAssignJob < ApplicationJob
  queue_as :default
  discard_on ActiveRecord::RecordNotFound
  MAX_DEPTH = 3

  def perform(conversation_id, depth: 0)
    return if depth > MAX_DEPTH
    Assignments::AutoAssign.call(Conversation.find(conversation_id))
  end
end
```

- [ ] **Step 3: Update existing AutoAssignJob spec** (`spec/jobs/auto_assign_job_spec.rb`) — confirm the new kwarg compiles against the existing test. Tests using `perform_now(id)` continue to work; tests using `perform_later(id)` also work.

- [ ] **Step 4: Pass + commit**

```bash
git add packages/app/app/jobs/auto_assign_job.rb packages/app/spec/jobs/auto_assign_job_depth_spec.rb
git commit -m "feat(autoassign): depth parameter on AutoAssignJob (max 3 to break loops)"
```

---

## Task 2: `Conversations::ResolveOrCreate` initial status

**Files:**
- Modify: `packages/app/app/services/conversations/resolve_or_create.rb`
- Test: extend `packages/app/spec/services/conversations/resolve_or_create_spec.rb` (or create if missing)

- [ ] **Step 1: Read** `resolve_or_create.rb` to find the `Conversation.create!(...)` call. Determine the existing status default.

- [ ] **Step 2: Failing spec — add to the existing file**

```ruby
it "creates conversation in 'bot' status when channel has active_flow" do
  channel = Channel.create!(name: "c", channel_type: "whatsapp_cloud", identifier: "c-1")
  flow = Flow.create!(name: "f")
  root = FlowNode.create!(flow: flow, node_type: "message", content: {"text" => "hi"})
  flow.update!(root_node: root)
  channel.update!(active_flow: flow)
  contact = Contact.create!
  cc = ContactChannel.create!(contact: contact, channel: channel, source_id: "s")

  result = described_class.call(contact_channel: cc, contact: contact, channel: channel)
  conv = result.is_a?(Array) ? result.first : result
  expect(conv.status).to eq("bot")
end

it "creates conversation in 'queued' status when no active_flow" do
  channel = Channel.create!(name: "c", channel_type: "whatsapp_cloud", identifier: "c-2", active_flow: nil)
  contact = Contact.create!
  cc = ContactChannel.create!(contact: contact, channel: channel, source_id: "s")

  result = described_class.call(contact_channel: cc, contact: contact, channel: channel)
  conv = result.is_a?(Array) ? result.first : result
  expect(conv.status).to eq("queued")
end
```

- [ ] **Step 3: Patch the create call**

```ruby
status = channel.active_flow_id.present? ? "bot" : "queued"
Conversation.create!(channel: channel, contact: contact, contact_channel: contact_channel, status: status, ...)
```

- [ ] **Step 4: Pass + commit**

```bash
git add packages/app/app/services/conversations/resolve_or_create.rb packages/app/spec/services/conversations/resolve_or_create_spec.rb
git commit -m "feat(conversations): initial status 'bot' on flow channels, 'queued' otherwise"
```

---

## Task 3: `Ingestion::ProcessMessage` integration

**Files:**
- Modify: `packages/app/app/services/ingestion/process_message.rb`
- Test: `packages/app/spec/services/ingestion/process_message_flow_spec.rb`

- [ ] **Step 1: Failing spec — focused on the branching**

```ruby
require "rails_helper"
RSpec.describe "Ingestion::ProcessMessage flow integration" do
  include ActiveJob::TestHelper

  let(:flow) { Flow.create!(name: "f") }
  let!(:root) { FlowNode.create!(flow: flow, node_type: "menu", content: {"text" => "?", "options" => [{"key" => "1", "label" => "x", "next_node_id" => nil}]}).tap { |n| flow.update!(root_node: n) } }
  let(:channel) { Channel.create!(name: "c", channel_type: "whatsapp_cloud", identifier: "c-flow", active_flow: flow) }

  def build_payload(channel:, content: "Oi", source_id: SecureRandom.hex(4))
    # Match the schema Plan 04 uses for the common payload.
    {
      "type" => "inbound_message",
      "channel" => {"type" => channel.channel_type, "identifier" => channel.identifier},
      "contact" => {"source_id" => source_id, "name" => "Customer"},
      "message" => {"external_id" => SecureRandom.hex(6), "content" => content, "content_type" => "text"},
      "metadata" => {}
    }
  end

  it "calls Flows::Start when conversation_flow is nil + status bot" do
    expect(Flows::Start).to receive(:call).and_call_original
    Ingestion::ProcessMessage.call(build_payload(channel: channel))
  end

  it "calls Flows::Advance on subsequent inbound messages" do
    Ingestion::ProcessMessage.call(build_payload(channel: channel, source_id: "55119"))
    # cf created by Start; next inbound should advance
    expect(Flows::Advance).to receive(:call).and_call_original
    Ingestion::ProcessMessage.call(build_payload(channel: channel, source_id: "55119", content: "1"))
  end

  it "skips flow engine when channel has no active_flow" do
    bare = Channel.create!(name: "bare", channel_type: "whatsapp_cloud", identifier: "bare-1")
    expect(Flows::Start).not_to receive(:call)
    expect(Flows::Advance).not_to receive(:call)
    Ingestion::ProcessMessage.call(build_payload(channel: bare))
  end

  it "does NOT enqueue AutoAssignJob for new bot conversations on flow channels" do
    expect {
      Ingestion::ProcessMessage.call(build_payload(channel: channel))
    }.not_to have_enqueued_job(AutoAssignJob)
  end

  it "still enqueues AutoAssignJob for new queued conversations on non-flow channels" do
    bare = Channel.create!(name: "bare2", channel_type: "whatsapp_cloud", identifier: "bare-2", auto_assign: true,
      auto_assign_config: {"strategy" => "round_robin"})
    ChannelTeam.create!(channel: bare, team: Team.create!(name: "T"))
    expect {
      Ingestion::ProcessMessage.call(build_payload(channel: bare))
    }.to have_enqueued_job(AutoAssignJob)
  end
end
```

- [ ] **Step 2: Patch `process_message.rb`**

Find the existing `Messages::Create.call(...)` and the existing `AutoAssignJob.perform_later` block from Plan 06a. Restructure:

```ruby
# Existing code creates the message…
message = Messages::Create.call(...)

# New flow-engine hook
if conversation.status == "bot" && conversation.channel.active_flow_id.present?
  if conversation.conversation_flow.nil?
    Flows::Start.call(conversation)
  else
    Flows::Advance.call(conversation, message)
  end
elsif conversation_created && conversation.status == "queued"
  # existing AutoAssignJob enqueue from Plan 06a, untouched
  ActiveRecord::Base.connection.current_transaction.after_commit do
    AutoAssignJob.perform_later(conversation.id)
  end
end
```

(Use whatever transaction-commit hook Plan 06a actually used; do not invent.)

- [ ] **Step 3: Pass + commit**

```bash
git add packages/app/app/services/ingestion/process_message.rb \
        packages/app/spec/services/ingestion/process_message_flow_spec.rb
git commit -m "feat(ingestion): wire Flows::Start/Advance into ProcessMessage"
```

---

## Task 4: `Flows::Handoff` uses `depth: 0`

**Files:**
- Modify: `packages/app/app/services/flows/handoff.rb` (from 07b)

- [ ] **Step 1: Change the call**

```ruby
AutoAssignJob.perform_later(@conversation.id, depth: 0)
```

- [ ] **Step 2: Update `handoff_spec.rb`** assertion to match.

- [ ] **Step 3: Pass + commit**

```bash
git add packages/app/app/services/flows/handoff.rb packages/app/spec/services/flows/handoff_spec.rb
git commit -m "chore(flows): Handoff passes depth: 0 to AutoAssignJob"
```

---

## Task 5: End-to-end bot cycle integration spec

**Files:**
- Create: `packages/app/spec/integration/bot_cycle_spec.rb`

- [ ] **Step 1: Spec**

```ruby
require "rails_helper"
RSpec.describe "Bot cycle (inbound → bot → handoff → auto-assign)", type: :integration do
  include ActiveJob::TestHelper

  let!(:vendas) { Team.create!(name: "Vendas") }
  let!(:agent)  { User.create!(name: "Agent", email_address: "a@x", password: "abcdef12", role: "agent", availability: "online").tap { |u| TeamMember.create!(user: u, team: vendas) } }
  let!(:channel) { Channel.create!(name: "wa", channel_type: "whatsapp_cloud", identifier: "wa-flow", auto_assign: true, auto_assign_config: {"strategy" => "round_robin"}).tap { |c| ChannelTeam.create!(channel: c, team: vendas) } }

  let!(:flow) { Flow.create!(name: "Atendimento") }
  let!(:greeting) { FlowNode.create!(flow: flow, node_type: "message", content: {"text" => "Olá!"}) }
  let!(:ask)      { FlowNode.create!(flow: flow, node_type: "collect", content: {"text" => "Nome?", "variable" => "contact_name", "validation" => "any"}) }
  let!(:handoff)  { FlowNode.create!(flow: flow, node_type: "handoff", content: {"team_id" => vendas.id, "message" => "Transferindo…", "assign_collected_name" => true}) }
  let!(:menu)     { FlowNode.create!(flow: flow, node_type: "menu", content: {"text" => "Como ajudar?", "options" => [{"key" => "1", "label" => "Vendas", "next_node_id" => handoff.id}]}) }

  before do
    greeting.update!(next_node: ask)
    ask.update!(next_node: menu)
    flow.update!(root_node: greeting)
    channel.update!(active_flow: flow)
  end

  def payload(content, source_id: "55119")
    {"type" => "inbound_message",
     "channel" => {"type" => channel.channel_type, "identifier" => channel.identifier},
     "contact" => {"source_id" => source_id, "name" => "Provider"},
     "message" => {"external_id" => SecureRandom.hex(6), "content" => content, "content_type" => "text"},
     "metadata" => {}}
  end

  it "runs the full cycle" do
    perform_enqueued_jobs do
      Ingestion::ProcessMessage.call(payload("Oi"))                # → greeting + ask prompt
      conv = Conversation.last
      expect(conv.status).to eq("bot")
      expect(conv.messages.where(direction: "outbound").count).to be >= 2

      Ingestion::ProcessMessage.call(payload("Maria"))             # → collect → menu prompt
      Ingestion::ProcessMessage.call(payload("1"))                 # → handoff
      conv.reload
      expect(conv.status).to eq("queued").or eq("assigned")
      expect(conv.team).to eq(vendas)
      expect(conv.contact.name).to eq("Maria")

      # AutoAssign should have run inline via perform_enqueued_jobs
      expect(conv.assignee).to eq(agent)
      expect(conv.reload.status).to eq("assigned")
    end
  end
end
```

- [ ] **Step 2: Pass + commit**

```bash
git add packages/app/spec/integration/bot_cycle_spec.rb
git commit -m "test(integration): full bot cycle (greeting → collect → menu → handoff → auto-assign)"
```

---

## Task 6: Regression + PROGRESS

- [ ] **Step 1: Full suite + standardrb**

Run: `bundle exec rspec && bundle exec standardrb --fix`. Expected: all green.

- [ ] **Step 2: Update `docs/PROGRESS.md`** — flip 07c row Draft → In Progress, then Shipped after merge.

- [ ] **Step 3: PR + merge + sync + flip-to-Shipped**

```bash
git push -u origin plan-07c-flow-ingestion-integration
gh pr create --title "Plan 07c: Flow ingestion integration + auto-assign depth" --body-file docs/plans/07c-2026-05-15-flow-ingestion-integration.md
gh pr merge --squash --delete-branch
```

After merge: sync, flip row, commit `docs(progress): Plan 07c shipped`, push.

---

You can now run `/clear` and `/execute-plan docs/plans/07d-2026-05-15-flow-management-dashboard.md`.
