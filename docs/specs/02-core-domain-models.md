# Spec: Core Domain Models & Audit Logging

> **Phase:** 2 (Core domain) — first half
> **Execution Order:** 2 of 7 — after Spec 1 *(can run in parallel with Spec 3)*
> **Date:** 2026-04-17
> **Status:** Draft — awaiting approval
> **Depends on:** [Spec 1: Monorepo Foundation](./01-monorepo-foundation.md)

---

## 1. What problem are we solving?

The Rails app exists (from Spec 1) but has no domain models. Before any feature — ingestion, outbound dispatch, workspace views, flow engine — can be built, the database schema must exist and the foundational principle of "audit-by-default" must be implemented. Every future spec assumes these tables and models are in place.

Additionally, the dashboard needs seed data to develop against: a dev account, users with different roles, teams, channels, and the wiring between them.

---

## 2. What is in scope?

### 2.1 Migrations

Generated via `bin/rails generate migration` and applied in the order documented in `ARCHITECTURE.md § Migration strategy`. Each migration is reversible. Enum columns get both model-level `enum` declarations and database-level check constraints (defense in depth).

**Migration order:**

1. **`CreateAccounts`** — `name` (string, NOT NULL), `locale` (string, default `pt-BR`), `auto_resolve_duration` (integer, default 7), timestamps.

2. **`ExtendUsers`** — The `users` table already exists from the Rails 8 auth generator (Spec 1). This migration **adds columns**: `account_id` (references, NOT NULL, FK), `name` (string, NOT NULL), `role` (string, NOT NULL, check constraint: `admin|supervisor|agent`), `availability` (string, default `offline`, check constraint: `online|busy|offline`).

3. **`CreateTeams`** — `account_id` (references, NOT NULL, FK), `name` (string, NOT NULL), timestamps.

4. **`CreateTeamMembers`** — `team_id` (references, NOT NULL, FK), `user_id` (references, NOT NULL, FK), timestamps. Unique index on `(team_id, user_id)`.

5. **`CreateChannels`** — `account_id` (references, NOT NULL, FK), `channel_type` (string, NOT NULL, check constraint: `whatsapp_cloud|zapi|evolution|instagram|telegram`), `identifier` (string, NOT NULL), `name` (string, NOT NULL), `active` (boolean, NOT NULL, default true), `config` (jsonb, NOT NULL, default `{}`), `credentials` (jsonb, NOT NULL, default `{}`), `auto_assign` (boolean, NOT NULL, default false), `auto_assign_config` (jsonb, NOT NULL, default `{}`), `greeting_enabled` (boolean, NOT NULL, default false), `greeting_message` (text), `lock_to_single_conversation` (boolean, NOT NULL, default false), `active_flow_id` (bigint, nullable), timestamps. Unique index on `(channel_type, identifier)`. Index on `(account_id, active)`. **Note: The foreign key constraint for `active_flow_id` is deferred to the Flow Engine spec to avoid circular FK dependencies.**

6. **`CreateChannelTeams`** — `channel_id` (references, NOT NULL, FK), `team_id` (references, NOT NULL, FK), timestamps. Unique index on `(channel_id, team_id)`.

7. **`CreateContacts`** — `account_id` (references, NOT NULL, FK), `name` (string), `email` (string), `phone_number` (string), `identifier` (string), `additional_attributes` (jsonb, NOT NULL, default `{}`), timestamps.

8. **`CreateContactChannels`** — `contact_id` (references, NOT NULL, FK), `channel_id` (references, NOT NULL, FK), `source_id` (string, NOT NULL), timestamps. Unique index on `(channel_id, source_id)`.

9. **`CreateConversations`** — `account_id` (references, NOT NULL, FK), `channel_id` (references, NOT NULL, FK), `contact_id` (references, NOT NULL, FK), `contact_channel_id` (references, NOT NULL, FK), `status` (string, NOT NULL, default `bot`, check constraint: `bot|queued|assigned|resolved`), `assignee_id` (references, nullable, FK to users), `team_id` (references, nullable, FK), `display_id` (integer, NOT NULL), `last_activity_at` (datetime), `additional_attributes` (jsonb, NOT NULL, default `{}`), timestamps. Indexes: `(account_id, status, last_activity_at DESC)`, `(channel_id, status)`, `(assignee_id, status)`, `(team_id, status)`, unique `(account_id, display_id)`, partial unique `(contact_channel_id) WHERE status != 'resolved'` (prevents concurrent creation of multiple open conversations for the same contact on a channel).

10. **`CreateMessages`** — `account_id` (references, NOT NULL, FK), `conversation_id` (references, NOT NULL, FK), `channel_id` (references, NOT NULL, FK), `direction` (string, NOT NULL, check constraint: `inbound|outbound`), `content` (text), `content_type` (string, NOT NULL, default `text`, check constraint: `text|image|audio|video|document|location|contact_card|input_select|button_reply|template`), `status` (string, NOT NULL, default `received`, check constraint: `received|pending|sent|delivered|read|failed`), `external_id` (string), `sender_type` (string), `sender_id` (bigint), `reply_to_external_id` (string), `error` (text), `metadata` (jsonb, NOT NULL, default `{}`), `raw` (jsonb), `sent_at` (datetime), timestamps. Indexes: `(conversation_id, created_at)`, partial unique `(channel_id, external_id) WHERE external_id IS NOT NULL`, `(sender_type, sender_id)`.

11. **`CreateAutomationRules`** — `account_id` (references, NOT NULL, FK), `event_name` (string, NOT NULL), `conditions` (jsonb, NOT NULL, default `[]`), `actions` (jsonb, NOT NULL, default `[]`), `active` (boolean, NOT NULL, default true), timestamps. Index on `(account_id, event_name, active)`.

12. **`CreateEvents`** — `account_id` (references, nullable), `name` (string, NOT NULL), `actor_type` (string), `actor_id` (bigint), `subject_type` (string, NOT NULL), `subject_id` (bigint, NOT NULL), `payload` (jsonb, NOT NULL, default `{}`), `created_at` (datetime, NOT NULL). **No `updated_at`** — events are immutable. Indexes: `(account_id, name, created_at DESC)`, `(subject_type, subject_id, created_at DESC)`, `(actor_type, actor_id, created_at DESC)`, `(account_id, created_at DESC)`.

13. **Active Storage install** — `bin/rails active_storage:install`.

> **Note:** Flows, FlowNodes, and ConversationFlows migrations are **deferred to the Flow Engine spec (Phase 6)**. The foreign key for `channels.active_flow_id` is also deferred. This keeps this spec focused on the core domain that all other specs depend on.

### 2.2 ActiveRecord Models

Each model includes:

- `belongs_to` / `has_many` associations matching the schema
- String-backed `enum` declarations with `validate: true`
- `validates` for required fields
- No `default_scope` — scoping is always explicit
- `encrypts :credentials` on `Channel`

**Models to create or extend:**

| Model | Key associations | Key validations |
|---|---|---|
| `Account` | `has_many :users, :teams, :channels, :contacts, :conversations, :messages, :events, :automation_rules` | `name` presence |
| `User` | `belongs_to :account`, `has_many :team_members`, `has_many :teams, through: :team_members`, `has_many :assigned_conversations, class_name: "Conversation", foreign_key: :assignee_id` | `name`, `email`, `role` presence; `email` uniqueness; `role` enum; `availability` enum |
| `Team` | `belongs_to :account`, `has_many :team_members`, `has_many :users, through: :team_members`, `has_many :channel_teams`, `has_many :channels, through: :channel_teams` | `name` presence |
| `TeamMember` | `belongs_to :team`, `belongs_to :user` | unique `(team_id, user_id)` |
| `Channel` | `belongs_to :account`, `has_many :channel_teams`, `has_many :teams, through: :channel_teams`, `has_many :contact_channels`, `has_many :conversations` | `channel_type`, `identifier`, `name` presence; unique `(channel_type, identifier)` scoped; `channel_type` enum; `encrypts :credentials` |
| `ChannelTeam` | `belongs_to :channel`, `belongs_to :team` | unique `(channel_id, team_id)` |
| `Contact` | `belongs_to :account`, `has_many :contact_channels`, `has_many :channels, through: :contact_channels`, `has_many :conversations` | — |
| `ContactChannel` | `belongs_to :contact`, `belongs_to :channel` | `source_id` presence; unique `(channel_id, source_id)` scoped |
| `Conversation` | `belongs_to :account`, `belongs_to :channel`, `belongs_to :contact`, `belongs_to :contact_channel`, `belongs_to :assignee, class_name: "User", optional: true`, `belongs_to :team, optional: true`, `has_many :messages` | `status` enum; `display_id` presence + uniqueness scoped to account |
| `Message` | `belongs_to :account`, `belongs_to :conversation`, `belongs_to :channel`, `belongs_to :sender, polymorphic: true, optional: true`, `has_many_attached :attachments` | `direction`, `content_type`, `status` enums |
| `AutomationRule` | `belongs_to :account` | `event_name` presence |
| `Event` | `belongs_to :account, optional: true`, `belongs_to :subject, polymorphic: true`, `belongs_to :actor, polymorphic: true, optional: true` | `name`, `subject_type`, `subject_id` presence |

### 2.3 `Events.emit` — foundational audit service

A single service that all future services will call. This is the implementation of the "audit-by-default" architectural principle.

```ruby
# app/services/events/emit.rb
class Events::Emit
  def self.call(name:, subject:, actor: nil, account: nil, payload: {})
    Event.create!(
      account: account || subject.try(:account),
      name: name,
      subject: subject,
      actor_type: actor_type_for(actor),
      actor_id: actor_id_for(actor),
      payload: payload
    )
  end
end
```

Key design decisions:
- `actor` can be a `User`, `Contact`, or the symbol `:system` / `:bot`. The service resolves the polymorphic fields.
- `account` is inferred from `subject.account` if not provided, but can be explicitly set for edge cases.
- Returns the created `Event` record.
- Raises on failure — events must never be silently dropped.

### 2.4 `Current` — thread-local context

Rails `Current` attributes for request-scoped context:

```ruby
# app/models/current.rb
class Current < ActiveSupport::CurrentAttributes
  attribute :user, :account
end
```

Set in the `ApplicationController` `before_action`. Used by services when `actor` defaults to `Current.user`. **Never used for scoping queries** — scoping is always explicit.

### 2.5 Seeds

`db/seeds.rb` creates the minimal dev environment:

- [ ] 1 Account: "FaleCom Dev"
- [ ] 1 Admin user: `admin@falecom.dev` / password `password`
- [ ] 1 Supervisor user: `supervisor@falecom.dev` / password `password`
- [ ] 1 Agent user: `agent@falecom.dev` / password `password`
- [ ] 2 Teams: "Vendas", "Suporte"
- [ ] Team membership: admin + agent in "Vendas", supervisor + agent in "Suporte"
- [ ] 2 Channels: WhatsApp Cloud (`whatsapp_cloud`, `5511999999999`, "WhatsApp Vendas"), Z-API (`zapi`, `5511888888888`, "Z-API Suporte")
- [ ] ChannelTeam wiring: "Vendas" attends both channels, "Suporte" attends both channels
- [ ] 2 Contacts: "João Silva", "Maria Santos"
- [ ] 2 ContactChannels: João on WhatsApp, Maria on Z-API
- [ ] 2 Conversations: one per contact, status `queued`, assigned to the agent
- [ ] Sample messages in each conversation (3–5 inbound + outbound)

Seeds must be idempotent — running `rails db:seed` twice does not create duplicates (use `find_or_create_by`).

### 2.6 RSpec Tests

- [ ] **Model specs** for every model: associations, validations, enums, encrypted attributes.
- [ ] **`Events::Emit` service spec**: verifies event creation with all actor types (User, Contact, :system, :bot), verifies it raises on invalid input, verifies immutability (no `updated_at`).
- [ ] **Migration round-trip test**: `rails db:migrate && rails db:rollback_all && rails db:migrate` — all migrations are reversible.

---

## 3. What is out of scope?

- **Dashboard views for conversations/messages** — deferred to a later spec. The models exist, the views do not.
- **Ingestion services** (`Ingestion::ProcessMessage`, `Contacts::Resolve`, etc.) — Spec 4 (Ingestion Pipeline).
- **Assignment/transfer services** — Spec 6 (Assignment, Transfer & Workspace).
- **Flow-related tables and models** (`flows`, `flow_nodes`, `conversation_flows`, `channels.active_flow_id`) — Spec 7 (Flow Engine).
- **Admin CRUD UI for channels/teams/users** — separate spec or part of a dashboard spec.
- **Real-time broadcasts** — Turbo Stream wiring comes when there are services that trigger broadcasts.

---

## 4. What changes about the system?

After this spec is executed:

- The database has all core domain tables with proper constraints, indexes, and foreign keys.
- Every model is tested with associations, validations, and enums.
- `Events::Emit` is available for all future services to use — the audit log is operational from this point forward.
- Seed data provides a realistic development environment: agents can be logged in, conversations and messages are visible in the console, and future UI specs have data to render.
- The `Current` model provides request-scoped context without introducing `default_scope`.

No contradictions with the architecture. This spec implements `ARCHITECTURE.md § FaleCom DB Schema` (minus flow tables) and `ARCHITECTURE.md § Audit`.

---

## 5. Acceptance criteria

1. `bin/rails db:migrate` succeeds with all migrations applied in order.
2. `bin/rails db:rollback` for each migration succeeds (reversibility).
3. `bin/rails db:seed` creates the complete dev dataset without errors. Running it twice creates no duplicates.
4. `bundle exec rspec spec/models/` — all model specs pass.
5. `bundle exec rspec spec/services/events/` — `Events::Emit` specs pass.
6. `bundle exec standardrb` passes.
7. `bin/rails console` — `Account.count`, `User.count`, `Channel.count`, `Conversation.count`, `Message.count` all return expected values.
8. `Event.create!(...).updated_at` raises or is not present — events are immutable.
9. `Channel.first.credentials` is encrypted at rest (verify via `ActiveRecord::Encryption`).

---

## 6. Risks

- **Users table extension** — the Rails 8 auth generator creates a `users` table with specific columns. Our migration adds to it. If the generator's schema changes between Rails versions, the migration may conflict. Mitigation: inspect the generated table structure before writing the extension migration.
- **Check constraints on enums** — string-backed enums with check constraints require careful wording. If a new enum value is added later, both the model `enum` declaration and the check constraint must be updated in a migration. Mitigation: document this in `packages/app/AGENTS.md` as a lesson learned.
- **Seed data maintenance** — seeds grow stale as the schema evolves. Mitigation: seeds are tested in CI by running `db:seed` after `db:prepare`.

---

## 7. Open questions

1. **`display_id` generation** — Should `display_id` be auto-incremented per account via a Postgres sequence, or generated in the `Conversations::Create` service via `account.conversations.maximum(:display_id).to_i + 1`? The sequence approach is safer under concurrent writes but more complex. Recommendation: use the service approach with a database advisory lock for the initial version; revisit if we see collisions.
2. **Contact merging** — The `contacts:merged` event is in the catalogue, but the `Contacts::Merge` service is not in scope for this spec. Should the `Contact` model include a `merged_into_id` column now, or defer it? Recommendation: defer. Add the column when the merge feature is speced.
