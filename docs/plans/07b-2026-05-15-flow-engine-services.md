# Plan 07b: Flow Engine Services

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans`.
> **Spec:** [07 — Flow Engine](../specs/07-flow-engine.md)
> **Date:** 2026-05-15
> **Status:** Draft — awaiting approval
> **Branch:** `plan-07b-flow-engine-services`
> **Depends on:** Plan 07a (Flow / FlowNode / ConversationFlow models).

**Goal:** Implement the core flow engine: `Flows::Start`, `Flows::Advance` (handlers for all 5 node types), `Flows::Handoff`. Plus a "Atendimento Vendas" seed flow exercising message → collect → menu → 3 handoff branches. After this plan, the engine works in isolation; Plan 07c wires it into ingestion.

**Architecture:** Three services, each a class-method entry-point. `Start` creates the `ConversationFlow`, picks `root_node` or `short_greeting_node` based on the inactivity threshold, then calls `Advance` with `inbound_message: nil` to execute the first node. `Advance` dispatches on `node.node_type`; `message` and `branch` nodes auto-chain (execute the next node immediately with `step_count + 1`); `menu` and `collect` send their prompt and return, waiting for the next inbound. The `MAX_STEPS_PER_ADVANCE = 50` guard prevents infinite loops — exceed it, abandon the flow, queue the conversation, emit `flows:abandoned`. `Handoff` sends the optional handoff message, applies `assign_collected_name`, completes the ConversationFlow, queues the conversation onto the target team, emits both `flows:handoff` and `conversations:status_changed`, and (if the channel has `auto_assign`) enqueues `AutoAssignJob` with `depth: 0` (the depth param is added to `AutoAssignJob` in Plan 07c; in this plan, mock/stub it in the spec).

**Tech Stack:** Ruby 4.0.2, Rails 8.1.3, RSpec 7.1, `standardrb`. No new gems. Leverages `Dispatch::Outbound` (Spec 05), `Events::Emit` (Spec 02), and `AutoAssignJob` (Spec 06a).

---

## Files to touch

### Create — services

- `packages/app/app/services/flows/start.rb`
- `packages/app/app/services/flows/advance.rb`
- `packages/app/app/services/flows/handoff.rb`
- `packages/app/app/services/flows/menu_formatter.rb` (small helper used by `handle_menu`)
- `packages/app/app/services/flows/validators.rb` (validates `collect` input by validator name)

### Create — specs

- `packages/app/spec/services/flows/start_spec.rb`
- `packages/app/spec/services/flows/advance_spec.rb`
- `packages/app/spec/services/flows/handoff_spec.rb`
- `packages/app/spec/services/flows/menu_formatter_spec.rb`
- `packages/app/spec/services/flows/validators_spec.rb`

### Modify

- `packages/app/db/seeds.rb` — append the "Atendimento Vendas" seed flow per Spec 07 §2.10. Idempotent: `Flow.find_or_create_by!(name: "Atendimento Vendas")` + nodes via `find_or_create_by!`. Wire `Channel.find_by(channel_type: "whatsapp_cloud").active_flow = flow` on the existing dev channel.

---

## Order of operations

1. **`Flows::MenuFormatter`** — pure helper. Test first.
2. **`Flows::Validators`** — pure helper. Test first.
3. **`Flows::Handoff`** — independent of Advance. Build + test.
4. **`Flows::Advance`** — per node-type branch. Test each handler.
5. **`Flows::Start`** — wraps creating `ConversationFlow` + first `Advance.call`. Test inactivity-threshold logic.
6. **Seeds** — idempotent extension of `db/seeds.rb`.
7. **Regression + PROGRESS.**

Each task ends with a Conventional-Commit commit.

---

## What could go wrong

**Most likely:** `Dispatch::Outbound` was designed for human-actor outbound; calling it with `actor: :bot` may fail validation (Spec 05a's `Messages::Create` allows `sender: nil` for system messages — check). If `Dispatch::Outbound` requires `actor` to be a User, change the bot calls to use `sender: nil` system-message convention from Plan 06b (`direction: "outbound"`, `status: "received"`). Bot messages then bypass `SendMessageJob`. BUT the spec wants real provider delivery for bot greetings — verify by reading `Dispatch::Outbound`; if it accepts a Symbol `:bot` as `actor` (maybe storing `sender: nil`, `sent_at: nil`, `status: "pending"`), use it. Otherwise extend `Dispatch::Outbound` to accept a `:bot` actor by skipping the User assignment but keeping `status: "pending"` so `SendMessageJob` dispatches normally. Surface the decision in the first task's commit message.

**Least likely:** circular flow node refs trigger the 50-step guard correctly. Test it explicitly with two `message` nodes pointing at each other.

---

## Task 1: `Flows::MenuFormatter`

**Files:**
- Create: `packages/app/app/services/flows/menu_formatter.rb`
- Test: `packages/app/spec/services/flows/menu_formatter_spec.rb`

- [ ] **Step 1: Failing spec**

```ruby
require "rails_helper"

RSpec.describe Flows::MenuFormatter do
  it "formats text + numbered options" do
    content = {
      "text" => "Como posso ajudar?",
      "options" => [
        {"key" => "1", "label" => "Vendas"},
        {"key" => "2", "label" => "Suporte"}
      ]
    }
    out = described_class.call(content)
    expect(out).to eq("Como posso ajudar?\n\n1 - Vendas\n2 - Suporte")
  end
end
```

- [ ] **Step 2: Implement**

```ruby
module Flows
  class MenuFormatter
    def self.call(content)
      header = content["text"].to_s
      options = (content["options"] || []).map { |o| "#{o["key"]} - #{o["label"]}" }.join("\n")
      "#{header}\n\n#{options}"
    end
  end
end
```

- [ ] **Step 3: Pass + commit**

```bash
git add packages/app/app/services/flows/menu_formatter.rb packages/app/spec/services/flows/menu_formatter_spec.rb
git commit -m "feat(flows): MenuFormatter helper"
```

---

## Task 2: `Flows::Validators`

**Files:**
- Create: `packages/app/app/services/flows/validators.rb`
- Test: `packages/app/spec/services/flows/validators_spec.rb`

- [ ] **Step 1: Failing spec**

```ruby
require "rails_helper"

RSpec.describe Flows::Validators do
  it "any → always true" do
    expect(described_class.call("anything", "any")).to be true
    expect(described_class.call("", "any")).to be true
  end

  it "email → only RFC-ish" do
    expect(described_class.call("a@b.co", "email")).to be true
    expect(described_class.call("nope", "email")).to be false
  end

  it "phone → digits only with optional + and length ≥ 8" do
    expect(described_class.call("+5511999999999", "phone")).to be true
    expect(described_class.call("11999999", "phone")).to be true
    expect(described_class.call("abc", "phone")).to be false
  end

  it "number → integer-coercible" do
    expect(described_class.call("42", "number")).to be true
    expect(described_class.call("abc", "number")).to be false
  end

  it "unknown validator defaults to any" do
    expect(described_class.call("x", "wat")).to be true
  end
end
```

- [ ] **Step 2: Implement**

```ruby
module Flows
  class Validators
    EMAIL = /\A[^\s@]+@[^\s@]+\.[^\s@]+\z/
    PHONE = /\A\+?\d{8,}\z/

    def self.call(value, kind)
      value = value.to_s
      case kind
      when "email"  then EMAIL.match?(value)
      when "phone"  then PHONE.match?(value.gsub(/\s/, ""))
      when "number" then value.match?(/\A-?\d+\z/)
      else true
      end
    end
  end
end
```

- [ ] **Step 3: Pass + commit**

```bash
git add packages/app/app/services/flows/validators.rb packages/app/spec/services/flows/validators_spec.rb
git commit -m "feat(flows): input Validators for collect nodes"
```

---

## Task 3: `Flows::Handoff`

**Files:**
- Create: `packages/app/app/services/flows/handoff.rb`
- Test: `packages/app/spec/services/flows/handoff_spec.rb`

- [ ] **Step 1: Failing spec**

```ruby
require "rails_helper"
RSpec.describe Flows::Handoff do
  include ActiveJob::TestHelper

  let(:channel) { Channel.create!(name: "c", channel_type: "whatsapp_cloud", identifier: "c-1", auto_assign: false) }
  let(:contact) { Contact.create!(name: "Provider-Name") }
  let(:cc)      { ContactChannel.create!(contact: contact, channel: channel, source_id: "s") }
  let(:conv)    { Conversation.create!(channel: channel, contact: contact, contact_channel: cc, display_id: 1, status: "bot") }
  let(:flow)    { Flow.create!(name: "f") }
  let(:cf)      { ConversationFlow.create!(conversation: conv, flow: flow, status: "active", state: {"contact_name" => "Real Name"}) }
  let(:team)    { Team.create!(name: "Vendas").tap { |t| ChannelTeam.create!(channel: channel, team: t) } }
  let(:node)    { FlowNode.create!(flow: flow, node_type: "handoff", content: {"team_id" => team.id, "message" => "Transferindo…", "assign_collected_name" => true}) }

  it "sends handoff message + completes flow + queues conversation" do
    expect { described_class.call(conv, cf, node) }
      .to change { conv.reload.status }.from("bot").to("queued")
      .and change { cf.reload.status }.from("active").to("completed")
      .and change { conv.messages.where(direction: "outbound").count }.by(1)
    expect(conv.team).to eq(team)
    expect(cf.reload.current_node).to be_nil
  end

  it "applies assign_collected_name overriding provider-reported name" do
    described_class.call(conv, cf, node)
    expect(contact.reload.name).to eq("Real Name")
  end

  it "skips name override when assign_collected_name false" do
    node.update!(content: node.content.merge("assign_collected_name" => false))
    described_class.call(conv, cf, node)
    expect(contact.reload.name).to eq("Provider-Name")
  end

  it "emits flows:handoff + conversations:status_changed" do
    expect { described_class.call(conv, cf, node) }
      .to change { Event.where(name: "flows:handoff", subject: conv).count }.by(1)
      .and change { Event.where(name: "conversations:status_changed", subject: conv).count }.by(1)
  end

  it "enqueues AutoAssignJob when channel.auto_assign? is true" do
    channel.update!(auto_assign: true)
    expect { described_class.call(conv, cf, node) }.to have_enqueued_job(AutoAssignJob)
  end

  it "no-op message when content has no 'message' key" do
    node.update!(content: {"team_id" => team.id})
    expect { described_class.call(conv, cf, node) }.not_to change { conv.messages.count }
  end
end
```

- [ ] **Step 2: Implement**

```ruby
module Flows
  class Handoff
    def self.call(conversation, conversation_flow, node = nil)
      new(conversation, conversation_flow, node).call
    end

    def initialize(conversation, conversation_flow, node)
      @conversation = conversation
      @cf = conversation_flow
      @content = (node&.content || {})
    end

    def call
      send_handoff_message
      apply_collected_name
      complete_flow
      queue_conversation
      emit_events
      enqueue_auto_assign
    end

    private

    def send_handoff_message
      return if @content["message"].blank?
      ::Dispatch::Outbound.call(
        conversation: @conversation,
        content: @content["message"],
        content_type: "text",
        actor: :bot
      )
    end

    def apply_collected_name
      return unless @content["assign_collected_name"]
      name = @cf.state["contact_name"]
      return if name.blank?
      @conversation.contact.update!(name: name)
    end

    def complete_flow
      @cf.update!(status: "completed", current_node: nil)
    end

    def queue_conversation
      team = @content["team_id"] ? Team.find_by(id: @content["team_id"]) : nil
      @conversation.update!(status: "queued", team: team)
    end

    def emit_events
      ::Events::Emit.call(name: "flows:handoff", subject: @conversation, actor: :bot, payload: {
        flow_id: @cf.flow_id, team_id: @conversation.team_id, collected_state: @cf.state
      })
      ::Events::Emit.call(name: "conversations:status_changed", subject: @conversation, actor: :bot, payload: {
        from: "bot", to: "queued"
      })
    end

    def enqueue_auto_assign
      return unless @conversation.channel.auto_assign?
      AutoAssignJob.perform_later(@conversation.id)
    end
  end
end
```

**Note on `Dispatch::Outbound` + `actor: :bot`:** If `Dispatch::Outbound` doesn't accept a Symbol actor, do ONE of:
- Extend `Dispatch::Outbound` to accept `actor: :bot` (it should map to `sender: nil` and keep `status: "pending"` so the message reaches the provider). Add a focused spec for that change in this task.
- Use `Messages::Create.call(...)` directly with `sender: nil, direction: "outbound", status: "pending"`, then `SendMessageJob.perform_later(message.id)` inline.

Pick the first option; it's cleaner. Commit the `Dispatch::Outbound` extension in a separate intermediate commit if needed.

**Note on AutoAssignJob `depth: 0`:** Spec 07 §2.6 asks `AutoAssignJob.perform_later(conversation_id, depth: 0)`. The current `AutoAssignJob#perform` signature (Plan 06a) takes only `conversation_id`. Plan 07c adds the `depth` parameter. In THIS plan, call `AutoAssignJob.perform_later(@conversation.id)` with the existing signature; 07c will update it.

- [ ] **Step 3: Pass + commit**

```bash
git add packages/app/app/services/flows/handoff.rb packages/app/spec/services/flows/handoff_spec.rb
git commit -m "feat(flows): Handoff service (queue + assign collected name + auto-assign)"
```

---

## Task 4: `Flows::Advance`

**Files:**
- Create: `packages/app/app/services/flows/advance.rb`
- Test: `packages/app/spec/services/flows/advance_spec.rb`

- [ ] **Step 1: Failing spec — cover each handler**

```ruby
require "rails_helper"
RSpec.describe Flows::Advance do
  include ActiveJob::TestHelper

  let(:channel) { Channel.create!(name: "c", channel_type: "whatsapp_cloud", identifier: "c-1") }
  let(:contact) { Contact.create!(name: "x") }
  let(:cc)      { ContactChannel.create!(contact: contact, channel: channel, source_id: "s") }
  let(:conv)    { Conversation.create!(channel: channel, contact: contact, contact_channel: cc, display_id: 1, status: "bot") }
  let(:flow)    { Flow.create!(name: "f") }

  describe "message node" do
    let(:n2)   { FlowNode.create!(flow: flow, node_type: "menu", content: {"text" => "?", "options" => [{"key" => "1", "label" => "x", "next_node_id" => nil}]}) }
    let(:msg)  { FlowNode.create!(flow: flow, node_type: "message", content: {"text" => "olá"}, next_node: n2) }
    let(:cf)   { ConversationFlow.create!(conversation: conv, flow: flow, current_node: msg, status: "active") }

    it "sends text + advances to next node + emits flows:advanced" do
      expect { described_class.call(conv, nil) }
        .to change { conv.messages.where(direction: "outbound").count }.by_at_least(1)
        .and change { Event.where(name: "flows:advanced", subject: conv).count }.by(1)
      expect(cf.reload.current_node).to eq(n2)
    end
  end

  describe "menu node" do
    let(:vendas) { FlowNode.create!(flow: flow, node_type: "handoff", content: {}) }
    let(:menu)   { FlowNode.create!(flow: flow, node_type: "menu", content: {"text" => "?", "options" => [{"key" => "1", "label" => "Vendas", "next_node_id" => nil}]}) }

    before do
      menu.content["options"][0]["next_node_id"] = vendas.id
      menu.save!
      ConversationFlow.create!(conversation: conv, flow: flow, current_node: menu, status: "active")
    end

    it "first hit (inbound_message: nil) sends menu, does NOT emit flows:advanced" do
      expect { described_class.call(conv, nil) }
        .to change { conv.messages.where(direction: "outbound").count }.by(1)
        .and not_change { Event.where(name: "flows:advanced", subject: conv).count }
    end

    it "valid selection advances + emits" do
      inbound = Message.create!(conversation: conv, channel: channel, direction: "inbound", content: "1", content_type: "text", status: "received")
      expect { described_class.call(conv, inbound) }
        .to change { Event.where(name: "flows:advanced", subject: conv).count }.by(1)
    end

    it "invalid selection re-sends menu, NO flows:advanced" do
      inbound = Message.create!(conversation: conv, channel: channel, direction: "inbound", content: "xxx", content_type: "text", status: "received")
      expect { described_class.call(conv, inbound) }
        .to change { conv.messages.where(direction: "outbound").count }.by(1)
        .and not_change { Event.where(name: "flows:advanced", subject: conv).count }
    end
  end

  describe "collect node" do
    let(:next_n) { FlowNode.create!(flow: flow, node_type: "message", content: {"text" => "ok"}) }
    let(:coll)   { FlowNode.create!(flow: flow, node_type: "collect", content: {"text" => "nome?", "variable" => "contact_name", "validation" => "any"}, next_node: next_n) }
    let(:cf)     { ConversationFlow.create!(conversation: conv, flow: flow, current_node: coll, status: "active") }

    it "first hit sends prompt, no advance" do
      expect { described_class.call(conv, nil) }
        .to change { conv.messages.where(direction: "outbound").count }.by(1)
      expect(cf.reload.current_node).to eq(coll)
    end

    it "valid input stores in state, advances" do
      inbound = Message.create!(conversation: conv, channel: channel, direction: "inbound", content: "Maria", content_type: "text", status: "received")
      described_class.call(conv, inbound)
      expect(cf.reload.state["contact_name"]).to eq("Maria")
      expect(cf.reload.current_node).to eq(next_n)
    end

    it "invalid (email validator + non-email) re-prompts, no advance" do
      coll.update!(content: coll.content.merge("validation" => "email"))
      inbound = Message.create!(conversation: conv, channel: channel, direction: "inbound", content: "not-email", content_type: "text", status: "received")
      expect { described_class.call(conv, inbound) }
        .to change { conv.messages.where(direction: "outbound").count }.by(1)
      expect(cf.reload.current_node).to eq(coll)
    end
  end

  describe "branch node" do
    let(:a) { FlowNode.create!(flow: flow, node_type: "message", content: {"text" => "A"}) }
    let(:b) { FlowNode.create!(flow: flow, node_type: "message", content: {"text" => "B"}) }
    let(:branch) { FlowNode.create!(flow: flow, node_type: "branch", content: {"variable" => "dept", "conditions" => [{"value" => "vendas", "next_node_id" => nil}], "default_next_node_id" => nil}) }
    let!(:cf) { ConversationFlow.create!(conversation: conv, flow: flow, current_node: branch, status: "active", state: {"dept" => "vendas"}) }

    before do
      branch.content["conditions"][0]["next_node_id"] = a.id
      branch.content["default_next_node_id"] = b.id
      branch.save!
    end

    it "routes via matching condition" do
      described_class.call(conv, nil)
      expect(cf.reload.current_node).to eq(a)
    end

    it "falls back to default when no match" do
      cf.update!(state: {"dept" => "other"})
      described_class.call(conv, nil)
      expect(cf.reload.current_node).to eq(b)
    end
  end

  describe "handoff node" do
    let(:hand) { FlowNode.create!(flow: flow, node_type: "handoff", content: {}) }
    let!(:cf) { ConversationFlow.create!(conversation: conv, flow: flow, current_node: hand, status: "active") }

    it "delegates to Flows::Handoff" do
      expect(Flows::Handoff).to receive(:call).with(conv, cf, hand)
      described_class.call(conv, nil)
    end
  end

  describe "infinite loop guard" do
    let!(:a) { FlowNode.create!(flow: flow, node_type: "message", content: {"text" => "a"}) }
    let!(:b) { FlowNode.create!(flow: flow, node_type: "message", content: {"text" => "b"}, next_node: a) }

    before do
      a.update!(next_node: b)
      ConversationFlow.create!(conversation: conv, flow: flow, current_node: a, status: "active")
    end

    it "abandons after MAX_STEPS_PER_ADVANCE" do
      expect { described_class.call(conv, nil) }
        .to change { conv.reload.status }.from("bot").to("queued")
        .and change { Event.where(name: "flows:abandoned", subject: conv).count }.by(1)
    end
  end

  describe "missing / dead conversation_flow" do
    it "restarts flow when conversation_flow is nil and channel has active_flow" do
      flow2 = Flow.create!(name: "f2")
      root = FlowNode.create!(flow: flow2, node_type: "message", content: {"text" => "hi"})
      flow2.update!(root_node: root)
      channel.update!(active_flow: flow2)
      expect(Flows::Start).to receive(:call).with(conv)
      described_class.call(conv, nil)
    end
  end
end
```

- [ ] **Step 2: Implement**

```ruby
module Flows
  class Advance
    MAX_STEPS_PER_ADVANCE = 50

    def self.call(conversation, inbound_message, step_count: 0)
      new(conversation, inbound_message, step_count).call
    end

    def initialize(conversation, inbound_message, step_count)
      @conversation = conversation
      @inbound = inbound_message
      @step = step_count
    end

    def call
      return abandon! if @step > MAX_STEPS_PER_ADVANCE

      cf = @conversation.conversation_flow
      return Flows::Start.call(@conversation) if cf.nil? || cf.status != "active"

      node = cf.current_node
      return Flows::Handoff.call(@conversation, cf) unless node

      send("handle_#{node.node_type}", cf, node)
    end

    private

    def handle_message(cf, node)
      send_text(node.content["text"])
      advance_to(cf, node.next_node_id, node)
      auto_chain(cf)
    end

    def handle_menu(cf, node)
      if @inbound.nil?
        send_text(Flows::MenuFormatter.call(node.content))
        return
      end
      selected = (node.content["options"] || []).find { |o| o["key"] == @inbound.content.to_s.strip }
      if selected
        advance_to(cf, selected["next_node_id"], node)
        auto_chain(cf)
      else
        send_text("Não entendi. Por favor, escolha uma opção:\n\n#{Flows::MenuFormatter.call(node.content)}")
      end
    end

    def handle_collect(cf, node)
      if @inbound.nil?
        send_text(node.content["text"])
        return
      end
      value = @inbound.content.to_s.strip
      if Flows::Validators.call(value, node.content["validation"])
        cf.update!(state: cf.state.merge(node.content["variable"] => value))
        advance_to(cf, node.next_node_id, node)
        auto_chain(cf)
      else
        send_text("Resposta inválida. #{node.content["text"]}")
      end
    end

    def handle_branch(cf, node)
      var = node.content["variable"]
      val = cf.state[var]
      condition = (node.content["conditions"] || []).find { |c| c["value"] == val }
      next_id = condition ? condition["next_node_id"] : node.content["default_next_node_id"]
      advance_to(cf, next_id, node)
      auto_chain(cf)
    end

    def handle_handoff(cf, node)
      Flows::Handoff.call(@conversation, cf, node)
    end

    def advance_to(cf, next_node_id, current_node)
      cf.update!(current_node_id: next_node_id, last_interaction_at: Time.current)
      Events::Emit.call(name: "flows:advanced", subject: @conversation, actor: :bot,
        payload: {node_id: current_node.id, node_type: current_node.node_type})
    end

    def auto_chain(cf)
      cf.reload
      next_node = cf.current_node
      return unless next_node
      return unless %w[message branch handoff].include?(next_node.node_type)
      Flows::Advance.call(@conversation, nil, step_count: @step + 1)
    end

    def send_text(content)
      ::Dispatch::Outbound.call(conversation: @conversation, content: content, content_type: "text", actor: :bot)
    end

    def abandon!
      cf = @conversation.conversation_flow
      cf&.update!(status: "abandoned")
      @conversation.update!(status: "queued")
      Events::Emit.call(name: "flows:abandoned", subject: @conversation, actor: :bot, payload: {
        reason: "max_steps_exceeded", step_count: @step
      })
    end
  end
end
```

- [ ] **Step 3: Pass + commit**

```bash
git add packages/app/app/services/flows/advance.rb packages/app/spec/services/flows/advance_spec.rb
git commit -m "feat(flows): Advance engine with handlers for all node types + loop guard"
```

---

## Task 5: `Flows::Start`

**Files:**
- Create: `packages/app/app/services/flows/start.rb`
- Test: `packages/app/spec/services/flows/start_spec.rb`

- [ ] **Step 1: Failing spec**

```ruby
require "rails_helper"
RSpec.describe Flows::Start do
  let(:channel) { Channel.create!(name: "c", channel_type: "whatsapp_cloud", identifier: "c-1") }
  let(:contact) { Contact.create!(name: "x") }
  let(:cc)      { ContactChannel.create!(contact: contact, channel: channel, source_id: "s") }
  let(:conv)    { Conversation.create!(channel: channel, contact: contact, contact_channel: cc, display_id: 1, status: "bot") }
  let(:flow)    { Flow.create!(name: "f", inactivity_threshold_hours: 24) }
  let!(:root)   { FlowNode.create!(flow: flow, node_type: "message", content: {"text" => "Olá"}).tap { |n| flow.update!(root_node: n) } }
  let!(:short)  { FlowNode.create!(flow: flow, node_type: "message", content: {"text" => "Bem-vindo de volta"}).tap { |n| flow.update!(short_greeting_node: n) } }

  before { channel.update!(active_flow: flow) }

  it "no-op when channel has no active_flow" do
    channel.update!(active_flow: nil)
    expect { described_class.call(conv) }.not_to change(ConversationFlow, :count)
  end

  it "no-op when active_flow.is_active is false" do
    flow.update!(is_active: false)
    expect { described_class.call(conv) }.not_to change(ConversationFlow, :count)
  end

  it "creates ConversationFlow starting at root_node when no recent activity" do
    described_class.call(conv)
    cf = conv.reload.conversation_flow
    expect(cf).to be_present
  end

  it "starts at short_greeting_node when recent activity exists" do
    prior_conv = Conversation.create!(channel: channel, contact: contact, contact_channel: cc, display_id: 2, status: "resolved")
    Message.create!(conversation: prior_conv, channel: channel, direction: "inbound", content: "oi", content_type: "text", status: "received", created_at: 1.hour.ago)
    described_class.call(conv)
    cf = conv.reload.conversation_flow
    # short_greeting_node is a message node — after Advance runs it auto-chains; root was advanced past.
    # Easier assertion: the first emitted outbound message body should be "Bem-vindo de volta"
    last_outbound = conv.messages.where(direction: "outbound").order(:created_at).first
    expect(last_outbound.content).to eq("Bem-vindo de volta")
  end

  it "emits flows:started and immediately runs first node" do
    expect { described_class.call(conv) }
      .to change { Event.where(name: "flows:started", subject: conv).count }.by(1)
      .and change { conv.messages.where(direction: "outbound").count }.by_at_least(1)
  end
end
```

- [ ] **Step 2: Implement**

```ruby
module Flows
  class Start
    def self.call(conversation)
      channel = conversation.channel
      flow = channel.active_flow
      return unless flow&.is_active?

      greeting_node = pick_greeting_node(conversation, flow)

      ConversationFlow.create!(
        conversation: conversation,
        flow: flow,
        current_node: greeting_node,
        status: "active",
        started_at: Time.current
      )

      Events::Emit.call(name: "flows:started", subject: conversation, actor: :bot)
      Flows::Advance.call(conversation, nil)
    end

    def self.pick_greeting_node(conversation, flow)
      return flow.root_node if flow.short_greeting_node.nil?

      last_at = conversation.contact_channel
        .conversations
        .where.not(id: conversation.id)
        .joins(:messages)
        .maximum("messages.created_at")

      if last_at && (Time.current - last_at) < flow.inactivity_threshold_hours.hours
        flow.short_greeting_node
      else
        flow.root_node
      end
    end
  end
end
```

- [ ] **Step 3: Pass + commit**

```bash
git add packages/app/app/services/flows/start.rb packages/app/spec/services/flows/start_spec.rb
git commit -m "feat(flows): Start service with inactivity-threshold greeting selection"
```

---

## Task 6: Seeds — "Atendimento Vendas"

**Files:**
- Modify: `packages/app/db/seeds.rb`

- [ ] **Step 1: Append idempotent seed block**

```ruby
# Flow: Atendimento Vendas
flow = Flow.find_or_create_by!(name: "Atendimento Vendas") do |f|
  f.description = "Bot inicial de triagem"
  f.is_active = true
  f.inactivity_threshold_hours = 24
end

greeting = FlowNode.find_or_create_by!(flow: flow, node_type: "message", content: {"text" => "Olá! Bem-vindo ao FaleCom Dev. 👋"})
collect  = FlowNode.find_or_create_by!(flow: flow, node_type: "collect", content: {"text" => "Qual seu nome?", "variable" => "contact_name", "validation" => "any"})

vendas_team  = Team.find_or_create_by!(name: "Vendas")
suporte_team = Team.find_or_create_by!(name: "Suporte")

handoff_vendas  = FlowNode.find_or_create_by!(flow: flow, node_type: "handoff", content: {"team_id" => vendas_team.id, "message" => "Transferindo para Vendas...", "assign_collected_name" => true})
handoff_suporte = FlowNode.find_or_create_by!(flow: flow, node_type: "handoff", content: {"team_id" => suporte_team.id, "message" => "Transferindo para Suporte...", "assign_collected_name" => true})
handoff_outros  = FlowNode.find_or_create_by!(flow: flow, node_type: "handoff", content: {"team_id" => vendas_team.id, "message" => "Alguém vai te ajudar em breve!", "assign_collected_name" => true})

menu = FlowNode.find_or_create_by!(flow: flow, node_type: "menu", content: {
  "text" => "Como posso ajudar?",
  "options" => [
    {"key" => "1", "label" => "Vendas",   "next_node_id" => handoff_vendas.id},
    {"key" => "2", "label" => "Suporte",  "next_node_id" => handoff_suporte.id},
    {"key" => "3", "label" => "Outros",   "next_node_id" => handoff_outros.id}
  ]
})

greeting.update!(next_node: collect)
collect.update!(next_node: menu)
flow.update!(root_node: greeting)

if (wa = Channel.find_by(channel_type: "whatsapp_cloud"))
  wa.update!(active_flow: flow)
  ChannelTeam.find_or_create_by!(channel: wa, team: vendas_team)
  ChannelTeam.find_or_create_by!(channel: wa, team: suporte_team)
end
```

- [ ] **Step 2: Run seeds twice** to verify idempotency

```bash
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && bin/rails db:seed && bin/rails db:seed"
```

Expected: no errors, no duplicates.

- [ ] **Step 3: Commit**

```bash
git add packages/app/db/seeds.rb
git commit -m "feat(flows): seed 'Atendimento Vendas' bot flow"
```

---

## Task 7: Regression + PROGRESS

- [ ] **Step 1: Full suite + standardrb**

Run: `bundle exec rspec && bundle exec standardrb --fix`. Expected: green.

- [ ] **Step 2: Update `docs/PROGRESS.md`** — flip 07b row Draft → In Progress, then **Shipped** after merge.

- [ ] **Step 3: PR + merge + sync + flip-to-Shipped**

```bash
git push -u origin plan-07b-flow-engine-services
gh pr create --title "Plan 07b: Flow engine services" --body-file docs/plans/07b-2026-05-15-flow-engine-services.md
gh pr merge --squash --delete-branch
```

After merge: sync main, flip row, commit `docs(progress): Plan 07b shipped`, push.

---

You can now run `/clear` and `/execute-plan docs/plans/07c-2026-05-15-flow-ingestion-integration.md`.
