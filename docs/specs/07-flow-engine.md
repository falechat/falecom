# Spec: Flow Engine

> **Phase:** 6 (Flow Engine)
> **Execution Order:** 7 of 7 — after Spec 6 (last spec)
> **Date:** 2026-04-17
> **Status:** Draft — awaiting approval
> **Depends on:**
> - [Spec 2: Core Domain Models](./02-core-domain-models.md) (core tables exist)
> - [Spec 4: Ingestion Pipeline](./04-ingestion-pipeline.md) (messages enter the system)
> - [Spec 5: Outbound Dispatch](./05-outbound-dispatch.md) (bot can send replies)
> - [Spec 6: Assignment, Transfer & Workspace](./06-assignment-transfer-workspace.md) (handoff has a destination)

---

## 1. What problem are we solving?

When a contact sends their first message to a channel, most businesses don't want that message to go directly to a human agent. They want a bot to greet the contact, show a menu, collect basic information (name, reason for contact, department), and only then hand off to the correct team.

Without the Flow Engine, every inbound message on a channel with no flow goes straight to `queued` — meaning an agent must handle it from scratch, every time. The flow automates the repetitive first interaction and routes the conversation to the right team with context already collected.

The Flow Engine is **inline Ruby code** — it runs inside the message ingestion transaction, not via webhooks or external services. This keeps it fast, testable, and simple.

---

## 2. What is in scope?

### 2.1 Migrations

These tables are created now, deferred from Spec 2 to keep that spec focused on core domain.

**Migration 1: `CreateFlows`**
- `name` (string, NOT NULL)
- `description` (text)
- `is_active` (boolean, NOT NULL, default true)
- `inactivity_threshold_hours` (integer, NOT NULL, default 24)
- `root_node_id` (bigint, nullable) — FK added in a separate migration
- `short_greeting_node_id` (bigint, nullable) — optional FK to flow_nodes. If set, returning contacts (within inactivity threshold) start here instead of root_node
- timestamps

**Migration 2: `CreateFlowNodes`**
- `flow_id` (references, NOT NULL, FK)
- `node_type` (string, NOT NULL, check constraint: `message|menu|collect|handoff|branch`)
- `content` (jsonb, NOT NULL)
- `next_node_id` (references, nullable, self-FK to flow_nodes)
- timestamps

**Migration 3: `AddRootNodeIdToFlows`**
- `ALTER TABLE flows ADD CONSTRAINT fk_flows_root_node_id FOREIGN KEY (root_node_id) REFERENCES flow_nodes(id)`

**Migration 4: `AddActiveFlowIdForeignKeyToChannels`**
- `ALTER TABLE channels ADD CONSTRAINT fk_channels_active_flow_id FOREIGN KEY (active_flow_id) REFERENCES flows(id)`

**Migration 5: `CreateConversationFlows`**
- `conversation_id` (references, NOT NULL, FK)
- `flow_id` (references, NOT NULL, FK)
- `current_node_id` (references, nullable, FK to flow_nodes)
- `state` (jsonb, NOT NULL, default `{}`)
- `status` (string, NOT NULL, default `active`, check constraint: `active|completed|abandoned`)
- `started_at` (datetime, NOT NULL, default `CURRENT_TIMESTAMP`)
- `last_interaction_at` (datetime)
- timestamps
- Partial unique index on `(conversation_id) WHERE status = 'active'` — one active flow per conversation. Allows multiple completed/abandoned records for flow history and conversation reopen scenarios

### 2.2 Models

| Model | Key associations | Key validations |
|---|---|---|
| `Flow` | `has_many :flow_nodes`, `belongs_to :root_node, class_name: "FlowNode", optional: true`, `belongs_to :short_greeting_node, class_name: "FlowNode", optional: true` | `name` presence; `node_type` enum |
| `FlowNode` | `belongs_to :flow`, `belongs_to :next_node, class_name: "FlowNode", optional: true` | `node_type` enum; `content` presence |
| `ConversationFlow` | `belongs_to :conversation`, `belongs_to :flow`, `belongs_to :current_node, class_name: "FlowNode", optional: true` | `status` enum; unique `conversation_id` |

Update to `Channel`:
- `belongs_to :active_flow, class_name: "Flow", optional: true`

### 2.3 Node Types and Content Schema

Each `node_type` has a specific `content` JSON structure:

**`message` — Send a text message and advance to the next node.**
```json
{
  "text": "Olá! Bem-vindo ao nosso atendimento. 👋"
}
```
Behavior: Send the text via `Dispatch::Outbound`, advance to `next_node_id`. No input expected from the contact.

**`menu` — Show options, wait for the contact to pick one.**
```json
{
  "text": "Como posso ajudar?",
  "options": [
    { "key": "1", "label": "Vendas", "next_node_id": 42 },
    { "key": "2", "label": "Suporte", "next_node_id": 43 },
    { "key": "3", "label": "Financeiro", "next_node_id": 44 }
  ]
}
```
Behavior: Send the text + formatted options. Wait for the contact's next message. Match the message to an option key. Advance to the matched option's `next_node_id`. If no match, re-send the menu with a "I didn't understand" prefix.

**`collect` — Ask for input, store it, advance.**
```json
{
  "text": "Qual seu nome completo?",
  "variable": "contact_name",
  "validation": "any"
}
```
Behavior: Send the text. Wait for input. Store the input in `conversation_flow.state[variable]`. Advance to `next_node_id`. Optional `validation` can be `any`, `email`, `phone`, `number`.

**`handoff` — Transfer to a human team.**
```json
{
  "team_id": 5,
  "message": "Transferindo você para a equipe de Vendas. Um momento, por favor!",
  "assign_collected_name": true
}
```
Behavior: Send the handoff message (if present). If `assign_collected_name` and `state["contact_name"]` exists, update the contact's name. Call `Flows::Handoff` which sets `conversation.status = "queued"` (or "assigned" via auto-assign), assigns the team, and emits `flows:handoff`. This is the terminal node for human escalation.

**`branch` — Conditional routing based on state.**
```json
{
  "variable": "contact_department",
  "conditions": [
    { "value": "vendas", "next_node_id": 50 },
    { "value": "suporte", "next_node_id": 51 }
  ],
  "default_next_node_id": 52
}
```
Behavior: Evaluate `state[variable]` against conditions. Advance to the matching `next_node_id`, or `default_next_node_id` if no match. No message sent, no input expected — this is pure routing logic.

### 2.4 `Flows::Start` Service

Initiates a flow for a new conversation.

```ruby
class Flows::Start
  def self.call(conversation)
    channel = conversation.channel
    flow = channel.active_flow
    return unless flow&.is_active?

    # Inactivity check: has this contact interacted recently on this channel?
    last_message_at = conversation.contact_channel
      .conversations
      .where.not(id: conversation.id)
      .joins(:messages)
      .maximum("messages.created_at")

    if last_message_at && (Time.current - last_message_at) < flow.inactivity_threshold_hours.hours
      # Recent interaction — use short greeting if configured, otherwise root
      greeting_node = flow.short_greeting_node || flow.root_node
    else
      greeting_node = flow.root_node
    end

    conversation_flow = ConversationFlow.create!(
      conversation: conversation,
      flow: flow,
      current_node: greeting_node,
      status: "active",
      started_at: Time.current
    )

    Events::Emit.call(name: "flows:started", subject: conversation, actor: :bot)

    # Immediately execute the first node (it's usually a message node)
    Flows::Advance.call(conversation, nil)
  end
end
```

### 2.5 `Flows::Advance` Service

The core flow engine. Called on every inbound message when `conversation.status == "bot"`.

```ruby
class Flows::Advance
  MAX_STEPS_PER_ADVANCE = 50

  def self.call(conversation, inbound_message, step_count: 0)
    # Guard against infinite loops from circular flow references
    if step_count > MAX_STEPS_PER_ADVANCE
      conversation_flow = conversation.conversation_flow
      conversation_flow&.update!(status: "abandoned")
      conversation.update!(status: "queued")
      Events::Emit.call(
        name: "flows:abandoned",
        subject: conversation,
        actor: :bot,
        payload: { reason: "max_steps_exceeded", step_count: step_count }
      )
      return
    end

    conversation_flow = conversation.conversation_flow
    if conversation_flow.nil? || !conversation_flow.active?
      # Flow exists but is dead (completed/abandoned) or missing.
      # Restart the flow if the conversation is still in 'bot' mode.
      return Flows::Start.call(conversation)
    end

    node = conversation_flow.current_node
    return Flows::Handoff.call(conversation, conversation_flow) unless node

    case node.node_type
    when "message"
      handle_message(conversation, conversation_flow, node, step_count)
    when "menu"
      handle_menu(conversation, conversation_flow, node, inbound_message, step_count)
    when "collect"
      handle_collect(conversation, conversation_flow, node, inbound_message, step_count)
    when "handoff"
      handle_handoff(conversation, conversation_flow, node)
    when "branch"
      handle_branch(conversation, conversation_flow, node, step_count)
    end

    # NOTE: flows:advanced is emitted ONLY inside handlers that actually advance
    # to a new node. Invalid menu selections and failed collect validations do
    # NOT emit this event. See handle_menu/handle_collect for the gating logic.
  end
end
```

**`handle_message`:**
```ruby
def handle_message(conversation, cf, node, step_count)
  Dispatch::Outbound.call(
    conversation: conversation,
    content: node.content["text"],
    content_type: "text",
    actor: :bot
  )
  advance_to(cf, node.next_node_id)
  emit_advanced_event(conversation, node)
  # If the next node is also a message or branch, execute it immediately
  # (don't wait for another inbound message)
  next_node = cf.reload.current_node
  if next_node && %w[message branch].include?(next_node.node_type)
    Flows::Advance.call(conversation, nil, step_count: step_count + 1)
  end
end
```

**`handle_menu`:**
```ruby
def handle_menu(conversation, cf, node, inbound_message, step_count)
  if inbound_message.nil?
    # First time hitting this node — send the menu
    formatted = format_menu(node.content)
    Dispatch::Outbound.call(conversation: conversation, content: formatted, content_type: "text", actor: :bot)
    return # Wait for the contact's response — no flows:advanced event
  end

  # Contact responded — match option
  selected = node.content["options"].find { |o| o["key"] == inbound_message.content.strip }
  if selected
    advance_to(cf, selected["next_node_id"])
    emit_advanced_event(conversation, node)  # only emit on actual advance
    next_node = cf.reload.current_node
    Flows::Advance.call(conversation, nil, step_count: step_count + 1) if next_node
  else
    # Invalid selection — re-send menu, no flows:advanced event
    Dispatch::Outbound.call(
      conversation: conversation,
      content: "Não entendi. Por favor, escolha uma opção:\n#{format_menu(node.content)}",
      content_type: "text",
      actor: :bot
    )
  end
end
```

**`handle_collect`:**
```ruby
def handle_collect(conversation, cf, node, inbound_message, step_count)
  if inbound_message.nil?
    Dispatch::Outbound.call(conversation: conversation, content: node.content["text"], content_type: "text", actor: :bot)
    return  # no flows:advanced event
  end

  value = inbound_message.content.strip
  if valid?(value, node.content["validation"])
    cf.state[node.content["variable"]] = value
    cf.save!
    advance_to(cf, node.next_node_id)
    emit_advanced_event(conversation, node)  # only emit on actual advance
    next_node = cf.reload.current_node
    Flows::Advance.call(conversation, nil, step_count: step_count + 1) if next_node
  else
    # Invalid input — re-send prompt, no flows:advanced event
    Dispatch::Outbound.call(
      conversation: conversation,
      content: "Resposta inválida. #{node.content["text"]}",
      content_type: "text",
      actor: :bot
    )
  end
end

def emit_advanced_event(conversation, node)
  Events::Emit.call(
    name: "flows:advanced",
    subject: conversation,
    actor: :bot,
    payload: { node_id: node.id, node_type: node.node_type }
  )
end
```

### 2.6 `Flows::Handoff` Service

Transfers the conversation from bot to human.

```ruby
class Flows::Handoff
  def self.call(conversation, conversation_flow, node = nil)
    content = node&.content || {}

    # Send handoff message if configured
    if content["message"].present?
      Dispatch::Outbound.call(
        conversation: conversation,
        content: content["message"],
        content_type: "text",
        actor: :bot
      )
    end

    # Apply collected data
    if content["assign_collected_name"] && conversation_flow.state["contact_name"].present?
      conversation.contact.update!(name: conversation_flow.state["contact_name"])
    end

    # Complete the flow
    conversation_flow.update!(status: "completed", current_node: nil)

    # Determine target team
    team = content["team_id"] ? Team.find(content["team_id"]) : nil

    # Update conversation status
    conversation.update!(
      status: "queued",
      team: team
    )

    Events::Emit.call(
      name: "flows:handoff",
      subject: conversation,
      actor: :bot,
      payload: {
        flow_id: conversation_flow.flow_id,
        team_id: team&.id,
        collected_state: conversation_flow.state
      }
    )

    Events::Emit.call(
      name: "conversations:status_changed",
      subject: conversation,
      actor: :bot,
      payload: { from: "bot", to: "queued" }
    )

    # Trigger auto-assign if configured
    if conversation.channel.auto_assign?
      # Pass a recursion depth to prevent infinite auto-assign loops
      AutoAssignJob.perform_later(conversation.id, depth: 0)
    end

    # Broadcast to workspace
    broadcast_handoff(conversation)
  end
end
```

### 2.7 Integration with `Ingestion::ProcessMessage`

Update the ingestion pipeline (from Spec 4) to call the flow engine:

```ruby
# Inside Ingestion::ProcessMessage, after Messages::Create:

if conversation.status == "bot" && conversation.channel.active_flow_id?
  if conversation.conversation_flow.nil?
    Flows::Start.call(conversation)
  else
    Flows::Advance.call(conversation, message)
  end
end
```

### 2.8 Flow Management — Dashboard (Simple Forms)

V1 uses Rails form-based editing, not a visual canvas builder.

**Routes:**
```
GET    /dashboard/flows                  → list all flows
POST   /dashboard/flows                  → create a new flow
GET    /dashboard/flows/:id              → edit flow (nodes list + add/edit forms)
PUT    /dashboard/flows/:id              → update flow metadata
DELETE /dashboard/flows/:id              → delete flow (only if not active on any channel)

POST   /dashboard/flows/:id/nodes        → add a node
PUT    /dashboard/flows/:id/nodes/:nid   → update a node
DELETE /dashboard/flows/:id/nodes/:nid   → remove a node

POST   /dashboard/channels/:id/activate_flow   → set channel.active_flow_id
DELETE /dashboard/channels/:id/deactivate_flow → clear channel.active_flow_id
```

**Flow edit page:**
- Flow name, description, inactivity threshold fields at the top.
- List of nodes in execution order (following `next_node_id` links from `root_node`).
- Each node is an expandable card showing its type and content.
- "Add node" button at the end of the chain.
- Node form varies by `node_type` (text input for message, key/label/target fields for menu, etc.).
- "Set as root" button on any node to change the flow's `root_node_id`.

### 2.9 Inactivity Threshold Logic

Per-flow setting controlling whether a returning contact sees the full menu or a short greeting.

```
When a new conversation starts on a channel with a flow:
  Look up the most recent inbound message from this contact_channel (across all conversations).
  Time since that message > flow.inactivity_threshold_hours?
    → YES: start from root_node (full menu)
    → NO:  start with a shorter greeting ("Como posso ajudar?")
```

The "short greeting" behavior is configurable per flow. V1 implementation: always start from root. The inactivity check determines only whether to skip a greeting message node.

### 2.10 Seeds

Extend `db/seeds.rb` with:
- 1 Flow: "Atendimento Vendas" with nodes:
  1. `message`: "Olá! Bem-vindo ao FaleCom Dev. 👋"
  2. `collect`: "Qual seu nome?" → variable `contact_name`
  3. `menu`: "Como posso ajudar?" → options: Vendas, Suporte, Outros
  4. `handoff` (Vendas): team=Vendas, message="Transferindo para Vendas..."
  5. `handoff` (Suporte): team=Suporte, message="Transferindo para Suporte..."
  6. `handoff` (Outros): team=Vendas, message="Alguém vai te ajudar em breve!"
- WhatsApp Vendas channel has `active_flow_id` set to this flow.

### 2.11 Tests

- [ ] **`Flows::Start` specs:**
  - Channel with active flow → ConversationFlow created, first node executed.
  - Channel without flow → no-op.
  - Inactivity threshold check (if implemented beyond v1 simplification).

- [ ] **`Flows::Advance` specs:**
  - `message` node → sends text, advances to next node.
  - `menu` node (first hit) → sends menu text, waits.
  - `menu` node (valid selection) → advances to selected option's node.
  - `menu` node (invalid selection) → re-sends menu.
  - `collect` node (first hit) → sends prompt, waits.
  - `collect` node (valid input) → stores in state, advances.
  - `branch` node → evaluates condition, routes correctly.
  - Terminal node (handoff) → calls `Flows::Handoff`.
  - Chained `message → message → menu` → first two execute immediately, menu waits.

- [ ] **`Flows::Handoff` specs:**
  - Conversation status changes to `queued`.
  - ConversationFlow status changes to `completed`.
  - Handoff message sent if configured.
  - Contact name updated if `assign_collected_name`.
  - `flows:handoff` and `conversations:status_changed` events emitted.
  - Auto-assign triggered if channel has it enabled.

- [ ] **Integration test — full bot cycle:**
  1. Contact sends "Oi" → conversation created (status: bot) → flow starts → greeting sent.
  2. Contact sends name → collected, menu sent.
  3. Contact sends "1" (Vendas) → handoff to Vendas team → conversation status: queued.
  4. If auto-assign enabled → conversation assigned to online agent.

- [ ] **Flow management specs:**
  - Create flow with nodes.
  - Edit node content.
  - Delete flow (only if not active on any channel).
  - Activate/deactivate flow on channel.

---

## 3. What is out of scope?

- **Visual flow builder** (drag-and-drop canvas) — roadmap item. V1 uses form-based editing.
- **Conditional logic beyond `branch`** — complex expressions, regex matching, API lookups. V1 has simple value matching.
- **Media messages from bot** — V1 bot sends text only. Images/documents from the flow is a follow-up.
- **Webhook nodes** — calling external APIs mid-flow. Roadmap item.
- **Flow versioning** — editing a flow that's running on active conversations. V1: edits take effect on the next conversation. Active `ConversationFlows` continue with the nodes they started with (nodes are linked by ID, not by snapshot).
- **Multiple flows per channel** — V1 is one active flow per channel.
- **A/B testing** of flow variants.

---

## 4. What changes about the system?

After this spec:

- Channels can have an active flow. Contacts messaging that channel interact with a bot before reaching a human.
- The bot collects information, routes to the correct team, and hands off with context.
- The full conversation lifecycle (bot → queued → assigned → resolved) is operational.
- Flow management is available in the dashboard (form-based, not visual).
- The ingestion pipeline now includes flow evaluation as part of message processing.

This implements `ARCHITECTURE.md § Flow Engine`, `§ Conversation Status Lifecycle`, `§ Inactivity and Flow Restart`, and `§ Build Order → Phase 6`.

---

## 5. Acceptance criteria

1. Contact sends message to channel with active flow → receives greeting message from bot.
2. Contact follows the flow: greeting → name collection → menu → selection → handoff message → conversation status is `queued`.
3. Collected contact name is applied to the Contact record.
4. Conversation is handed off to the correct team based on the flow's handoff node.
5. Invalid menu selection → bot re-sends the menu with "I didn't understand."
6. After handoff, if auto-assign is enabled → conversation is assigned to an online agent.
7. Flow edit page: admin can create a flow with multiple node types and link them.
8. Activating a flow on a channel → new conversations on that channel start in `bot` status.
9. Deactivating a flow → new conversations start in `queued` status.
10. `bundle exec rspec` passes. `bundle exec standardrb` passes.

---

## 6. Risks

- **Flow execution in-transaction** — `Flows::Advance` runs inside the ingestion transaction, including `Dispatch::Outbound` which enqueues `SendMessageJob`. If the transaction is slow, it blocks the ingest. Mitigation: `Dispatch::Outbound` only creates a DB record and enqueues a job — no external HTTP calls inside the transaction. The actual provider call happens async in the job.
- **Infinite loops** — a misconfigured flow with circular `next_node_id` references could loop forever. Mitigation: add a max-steps guard (e.g., 50 nodes per `Advance` call). If exceeded, auto-handoff with an error event.
- **Auto-Assign Loops** — If auto-assign triggers something that unassigns and re-queues, it could loop. Mitigation: `AutoAssignJob` accepts a `depth` parameter; if `depth > 3`, it aborts and leaves the conversation unassigned for human intervention.
- **Node deletion while in use** — deleting a FlowNode that a `ConversationFlow` currently points to would break the flow. Mitigation: soft-delete or disallow deleting nodes referenced by active conversation flows.

---

## 7. Open questions

1. **Flow versioning** — when an admin edits a flow, should active conversations see the changes or continue on the "old" flow? V1 recommendation: conversations continue with existing node links (nodes are referenced by ID). New conversations get the updated flow. No snapshot mechanism needed.
2. **Inactivity threshold implementation** — the architecture describes two greeting paths (full menu vs. short greeting). How do we define which node is the "short greeting"? Recommendation: add an optional `short_greeting_node_id` to the Flow model. If not set, always start from root.
3. **WhatsApp interactive messages** — Should the menu node send a WhatsApp interactive list/button message instead of plain text? Recommendation: yes, eventually. For v1, send a formatted text menu ("1 - Vendas\n2 - Suporte"). The outbound payload's `content_type` can be `text` for now; switch to `input_select` when WhatsApp interactive message support is added to the container's sender.
