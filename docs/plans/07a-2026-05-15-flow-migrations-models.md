# Plan 07a: Flow Migrations + Models

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans`.
> **Spec:** [07 — Flow Engine](../specs/07-flow-engine.md)
> **Date:** 2026-05-15
> **Status:** Draft — awaiting approval
> **Branch:** `plan-07a-flow-migrations-models`

**Goal:** Land the database schema and ActiveRecord models for the Flow Engine: `flows`, `flow_nodes`, `conversation_flows`, the `channels.active_flow_id` FK, plus `Flow`, `FlowNode`, `ConversationFlow` models and a `Channel#active_flow` association. After this plan, the schema is ready; no engine behavior yet. Plans 07b → 07d build on top.

**Architecture:** Five migrations in the order Spec 07 §2.1 dictates — create flows (without root_node FK), create flow_nodes, add root_node FK on flows, add active_flow_id FK on channels, create conversation_flows (with partial unique index on `conversation_id WHERE status = 'active'`). Models add the standard enums + validations + associations. `ConversationFlow` exposes a `Conversation#conversation_flow` `has_one` so `Ingestion::ProcessMessage` (07c) can call `conversation.conversation_flow`. The partial unique index allows multiple completed/abandoned records per conversation (history + reopen scenarios) while guaranteeing at most one active.

**Tech Stack:** Ruby 4.0.2, Rails 8.1.3, Postgres, RSpec 7.1, `standardrb`. No new gems.

---

## Files to touch

All paths relative to repo root. Commands inside `falecom-workspace-1` (`docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && …"`).

### Create — migrations

- `packages/app/db/migrate/<ts>_create_flows.rb`
- `packages/app/db/migrate/<ts>_create_flow_nodes.rb`
- `packages/app/db/migrate/<ts>_add_root_node_id_fk_to_flows.rb`
- `packages/app/db/migrate/<ts>_add_active_flow_id_fk_to_channels.rb`
- `packages/app/db/migrate/<ts>_create_conversation_flows.rb`

### Create — models

- `packages/app/app/models/flow.rb`
- `packages/app/app/models/flow_node.rb`
- `packages/app/app/models/conversation_flow.rb`

### Create — specs

- `packages/app/spec/models/flow_spec.rb`
- `packages/app/spec/models/flow_node_spec.rb`
- `packages/app/spec/models/conversation_flow_spec.rb`

### Modify

- `packages/app/app/models/channel.rb` — add `belongs_to :active_flow, class_name: "Flow", optional: true`.
- `packages/app/app/models/conversation.rb` — add `has_one :conversation_flow, dependent: :destroy`.
- `packages/app/db/seeds.rb` — leave alone for now; 07b extends seeds.

---

## Order of operations (TDD wave)

1. **Migration 1: `flows`** — schema only.
2. **Migration 2: `flow_nodes`** — schema + check constraint.
3. **Migration 3: `flows.root_node_id` FK** — needs flow_nodes to exist.
4. **Migration 4: `channels.active_flow_id` FK** — column already exists in schema; just add FK constraint.
5. **Migration 5: `conversation_flows`** — schema + partial unique index + check constraint.
6. **`Flow` model + spec**.
7. **`FlowNode` model + spec**.
8. **`ConversationFlow` model + spec**.
9. **`Channel#active_flow` + `Conversation#conversation_flow` associations** — light spec.
10. **Regression sweep + PROGRESS.**

Each task ends with a Conventional-Commit commit.

---

## What could go wrong

**Most likely:** the partial unique index on `conversation_flows (conversation_id) WHERE status = 'active'` collides with an attempt to create a second active flow during testing. That's the intended behavior — surface it as `ActiveRecord::RecordNotUnique` from the spec.

**Least likely:** the `channels.active_flow_id` column doesn't yet exist. Schema check from Spec 02 shows the column IS already present in `channels`. Migration 4 only adds the FK constraint — confirm with `\d channels` before writing the migration.

---

## Task 1: Migration — `create_flows`

**Files:**
- Create: `packages/app/db/migrate/<ts>_create_flows.rb`

- [ ] **Step 1: Generate migration**

```bash
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && bin/rails g migration CreateFlows"
```

- [ ] **Step 2: Edit migration**

```ruby
class CreateFlows < ActiveRecord::Migration[8.1]
  def change
    create_table :flows do |t|
      t.string :name, null: false
      t.text :description
      t.boolean :is_active, null: false, default: true
      t.integer :inactivity_threshold_hours, null: false, default: 24
      t.bigint :root_node_id
      t.bigint :short_greeting_node_id
      t.timestamps
    end

    add_index :flows, :is_active
  end
end
```

- [ ] **Step 3: Run + verify**

```bash
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && bin/rails db:migrate"
```

Expected: migration succeeds. `\d flows` shows all columns.

- [ ] **Step 4: Commit**

```bash
git add packages/app/db/migrate/*_create_flows.rb packages/app/db/schema.rb
git commit -m "feat(flows): create flows table"
```

---

## Task 2: Migration — `create_flow_nodes`

**Files:**
- Create: `packages/app/db/migrate/<ts>_create_flow_nodes.rb`

- [ ] **Step 1: Generate + edit**

```ruby
class CreateFlowNodes < ActiveRecord::Migration[8.1]
  def change
    create_table :flow_nodes do |t|
      t.references :flow, null: false, foreign_key: true
      t.string :node_type, null: false
      t.jsonb :content, null: false, default: {}
      t.references :next_node, foreign_key: {to_table: :flow_nodes}
      t.timestamps
    end

    add_check_constraint :flow_nodes,
      "node_type IN ('message','menu','collect','handoff','branch')",
      name: "flow_nodes_node_type_check"
  end
end
```

- [ ] **Step 2: Migrate + commit**

```bash
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && bin/rails db:migrate"
git add packages/app/db/migrate/*_create_flow_nodes.rb packages/app/db/schema.rb
git commit -m "feat(flows): create flow_nodes table with node_type check constraint"
```

---

## Task 3: Migration — `add_root_node_id_fk_to_flows`

**Files:**
- Create: `packages/app/db/migrate/<ts>_add_root_node_id_fk_to_flows.rb`

- [ ] **Step 1: Edit**

```ruby
class AddRootNodeIdFkToFlows < ActiveRecord::Migration[8.1]
  def change
    add_foreign_key :flows, :flow_nodes, column: :root_node_id
    add_foreign_key :flows, :flow_nodes, column: :short_greeting_node_id
    add_index :flows, :root_node_id
    add_index :flows, :short_greeting_node_id
  end
end
```

- [ ] **Step 2: Migrate + commit**

```bash
git add packages/app/db/migrate/*_add_root_node_id_fk_to_flows.rb packages/app/db/schema.rb
git commit -m "feat(flows): FK + index on flows.root_node_id and short_greeting_node_id"
```

---

## Task 4: Migration — `add_active_flow_id_fk_to_channels`

**Files:**
- Create: `packages/app/db/migrate/<ts>_add_active_flow_id_fk_to_channels.rb`

- [ ] **Step 1: Confirm column exists**

```bash
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && bin/rails runner 'puts Channel.columns_hash[\"active_flow_id\"].inspect'"
```

Expected: non-nil. If nil, add the column in this migration (`add_column :channels, :active_flow_id, :bigint`) and an `add_index`.

- [ ] **Step 2: Edit migration**

```ruby
class AddActiveFlowIdFkToChannels < ActiveRecord::Migration[8.1]
  def change
    add_foreign_key :channels, :flows, column: :active_flow_id
    add_index :channels, :active_flow_id unless index_exists?(:channels, :active_flow_id)
  end
end
```

- [ ] **Step 3: Migrate + commit**

```bash
git add packages/app/db/migrate/*_add_active_flow_id_fk_to_channels.rb packages/app/db/schema.rb
git commit -m "feat(flows): FK channels.active_flow_id -> flows"
```

---

## Task 5: Migration — `create_conversation_flows`

**Files:**
- Create: `packages/app/db/migrate/<ts>_create_conversation_flows.rb`

- [ ] **Step 1: Edit**

```ruby
class CreateConversationFlows < ActiveRecord::Migration[8.1]
  def change
    create_table :conversation_flows do |t|
      t.references :conversation, null: false, foreign_key: true
      t.references :flow, null: false, foreign_key: true
      t.references :current_node, foreign_key: {to_table: :flow_nodes}
      t.jsonb :state, null: false, default: {}
      t.string :status, null: false, default: "active"
      t.datetime :started_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :last_interaction_at
      t.timestamps
    end

    add_check_constraint :conversation_flows,
      "status IN ('active','completed','abandoned')",
      name: "conversation_flows_status_check"

    add_index :conversation_flows, :conversation_id,
      unique: true,
      where: "status = 'active'",
      name: "index_conversation_flows_one_active_per_conversation"
  end
end
```

- [ ] **Step 2: Migrate + commit**

```bash
git add packages/app/db/migrate/*_create_conversation_flows.rb packages/app/db/schema.rb
git commit -m "feat(flows): create conversation_flows table with partial unique index on active"
```

---

## Task 6: `Flow` model + spec

**Files:**
- Create: `packages/app/app/models/flow.rb`
- Test: `packages/app/spec/models/flow_spec.rb`

- [ ] **Step 1: Failing spec**

```ruby
require "rails_helper"

RSpec.describe Flow, type: :model do
  it "validates presence of name" do
    expect(Flow.new(name: nil)).not_to be_valid
  end

  it "defaults is_active to true and inactivity_threshold_hours to 24" do
    f = Flow.create!(name: "Atendimento")
    expect(f.is_active).to be true
    expect(f.inactivity_threshold_hours).to eq(24)
  end

  it "has_many flow_nodes (dependent: destroy)" do
    f = Flow.create!(name: "f")
    n = FlowNode.create!(flow: f, node_type: "message", content: {"text" => "hi"})
    expect { f.destroy }.to change(FlowNode, :count).by(-1)
    expect { n.reload }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "belongs_to root_node and short_greeting_node optionally" do
    f = Flow.create!(name: "f")
    expect(f.root_node).to be_nil
    expect(f.short_greeting_node).to be_nil
  end
end
```

- [ ] **Step 2: Run, fail. Implement:**

```ruby
class Flow < ApplicationRecord
  has_many :flow_nodes, dependent: :destroy
  belongs_to :root_node, class_name: "FlowNode", optional: true
  belongs_to :short_greeting_node, class_name: "FlowNode", optional: true

  validates :name, presence: true
end
```

- [ ] **Step 3: Pass + commit**

```bash
git add packages/app/app/models/flow.rb packages/app/spec/models/flow_spec.rb
git commit -m "feat(flows): Flow model"
```

---

## Task 7: `FlowNode` model + spec

**Files:**
- Create: `packages/app/app/models/flow_node.rb`
- Test: `packages/app/spec/models/flow_node_spec.rb`

- [ ] **Step 1: Failing spec**

```ruby
require "rails_helper"

RSpec.describe FlowNode, type: :model do
  let(:flow) { Flow.create!(name: "f") }

  it "validates node_type enum" do
    expect { FlowNode.create!(flow: flow, node_type: "lol", content: {}) }
      .to raise_error(ArgumentError)
  end

  it "validates content presence" do
    expect(FlowNode.new(flow: flow, node_type: "message", content: nil)).not_to be_valid
  end

  %w[message menu collect handoff branch].each do |t|
    it "accepts node_type=#{t}" do
      expect(FlowNode.create!(flow: flow, node_type: t, content: {"x" => 1})).to be_persisted
    end
  end

  it "belongs_to next_node optionally" do
    n1 = FlowNode.create!(flow: flow, node_type: "message", content: {"text" => "a"})
    n2 = FlowNode.create!(flow: flow, node_type: "message", content: {"text" => "b"}, next_node: n1)
    expect(n2.next_node).to eq(n1)
  end
end
```

- [ ] **Step 2: Implement**

```ruby
class FlowNode < ApplicationRecord
  belongs_to :flow
  belongs_to :next_node, class_name: "FlowNode", optional: true

  enum :node_type, {
    message: "message",
    menu: "menu",
    collect: "collect",
    handoff: "handoff",
    branch: "branch"
  }, validate: true

  validates :content, presence: true
end
```

- [ ] **Step 3: Pass + commit**

```bash
git add packages/app/app/models/flow_node.rb packages/app/spec/models/flow_node_spec.rb
git commit -m "feat(flows): FlowNode model with node_type enum"
```

---

## Task 8: `ConversationFlow` model + spec

**Files:**
- Create: `packages/app/app/models/conversation_flow.rb`
- Test: `packages/app/spec/models/conversation_flow_spec.rb`

- [ ] **Step 1: Failing spec**

```ruby
require "rails_helper"

RSpec.describe ConversationFlow, type: :model do
  let(:channel) { Channel.create!(name: "c", channel_type: "whatsapp_cloud", identifier: "c-1") }
  let(:contact) { Contact.create!(name: "x") }
  let(:cc)      { ContactChannel.create!(contact: contact, channel: channel, source_id: "s") }
  let(:conv)    { Conversation.create!(channel: channel, contact: contact, contact_channel: cc, display_id: 1) }
  let(:flow)    { Flow.create!(name: "f") }

  it "validates status enum" do
    expect { ConversationFlow.create!(conversation: conv, flow: flow, status: "lol") }
      .to raise_error(ArgumentError)
  end

  it "enforces one active flow per conversation" do
    ConversationFlow.create!(conversation: conv, flow: flow, status: "active")
    expect {
      ConversationFlow.create!(conversation: conv, flow: flow, status: "active")
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "allows multiple completed flows per conversation" do
    ConversationFlow.create!(conversation: conv, flow: flow, status: "completed")
    expect {
      ConversationFlow.create!(conversation: conv, flow: flow, status: "completed")
    }.not_to raise_error
  end

  it "defaults state to {}" do
    cf = ConversationFlow.create!(conversation: conv, flow: flow)
    expect(cf.state).to eq({})
    expect(cf.status).to eq("active")
  end
end
```

- [ ] **Step 2: Implement**

```ruby
class ConversationFlow < ApplicationRecord
  belongs_to :conversation
  belongs_to :flow
  belongs_to :current_node, class_name: "FlowNode", optional: true

  enum :status, {
    active: "active",
    completed: "completed",
    abandoned: "abandoned"
  }, validate: true
end
```

- [ ] **Step 3: Pass + commit**

```bash
git add packages/app/app/models/conversation_flow.rb packages/app/spec/models/conversation_flow_spec.rb
git commit -m "feat(flows): ConversationFlow model with status enum + partial unique"
```

---

## Task 9: Wire associations on Channel + Conversation

**Files:**
- Modify: `packages/app/app/models/channel.rb`
- Modify: `packages/app/app/models/conversation.rb`

- [ ] **Step 1: Edit `channel.rb`** — add line after existing associations:

```ruby
belongs_to :active_flow, class_name: "Flow", optional: true
```

- [ ] **Step 2: Edit `conversation.rb`** — add:

```ruby
has_one :conversation_flow, -> { where(status: "active") }, dependent: :destroy, inverse_of: :conversation
```

The scope ensures `conversation.conversation_flow` returns the active one. Multiple completed/abandoned rows are reachable via `conversation_flows` (no scope) if needed later — add `has_many :conversation_flows` for that:

```ruby
has_many :conversation_flows, dependent: :destroy
has_one :active_conversation_flow, -> { where(status: "active") }, class_name: "ConversationFlow", inverse_of: :conversation
```

Pick whichever shape Spec 07 §2.5 (`conversation.conversation_flow`) reads — the engine code uses `conversation.conversation_flow.nil? || !conversation_flow.active?`, so a `has_one :conversation_flow` returning the active one is fine. Use the scoped `has_one`.

- [ ] **Step 3: Light spec** — add to `conversation_spec.rb` (or create one if missing):

```ruby
it "exposes the active conversation_flow" do
  channel = Channel.create!(name: "c", channel_type: "whatsapp_cloud", identifier: "c-2")
  contact = Contact.create!(name: "x")
  cc = ContactChannel.create!(contact: contact, channel: channel, source_id: "s2")
  conv = Conversation.create!(channel: channel, contact: contact, contact_channel: cc, display_id: 99)
  flow = Flow.create!(name: "f")
  cf = ConversationFlow.create!(conversation: conv, flow: flow, status: "active")
  expect(conv.reload.conversation_flow).to eq(cf)
end
```

- [ ] **Step 4: Pass + commit**

```bash
git add packages/app/app/models/channel.rb packages/app/app/models/conversation.rb packages/app/spec/models/conversation_spec.rb
git commit -m "feat(flows): Channel#active_flow + Conversation#conversation_flow associations"
```

---

## Task 10: Regression + PROGRESS

- [ ] **Step 1: Full suite + standardrb**

```bash
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && bundle exec rspec && bundle exec standardrb --fix"
```

Expected: all green, no offenses.

- [ ] **Step 2: Update `docs/PROGRESS.md`** — flip Spec 07 row Draft → In Progress (add `07a` to its Plans column); add 07a Plans row with status **In Progress**; flip to **Shipped** after merge.

- [ ] **Step 3: Push, PR, merge**

```bash
git push -u origin plan-07a-flow-migrations-models
gh pr create --title "Plan 07a: Flow migrations + models" --body-file docs/plans/07a-2026-05-15-flow-migrations-models.md
gh pr merge --squash --delete-branch
```

- [ ] **Step 4: Sync main + flip 07a row to Shipped + commit + push**

---

You can now run `/clear` and `/execute-plan docs/plans/07b-2026-05-15-flow-engine-services.md`.
