# Plan 02: Core Domain Models & Audit Logging

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` to execute the parallel phases.
> **Spec:** [02 — Core Domain Models & Audit Logging](../specs/02-core-domain-models.md)
> **Date:** 2026-04-21
> **Status:** Approved (2026-04-21, self-reviewed)
> **Branch:** `spec-02-core-domain-models`

**Goal:** Implement the full core domain schema (11 migrations + 1 Active Storage install), matching ActiveRecord models, the `Events::Emit` audit service, the `Current` thread-local `:user` attribute, seed data, and RSpec coverage for every model + `Events::Emit`.

**Architecture:** Rails 8.1 app under `packages/app`. Postgres. String-backed enums with DB check constraints (defense in depth). Encrypted `Channel#credentials` via ActiveRecord Encryption. Events are immutable (no `updated_at`). Seeds idempotent (`find_or_create_by`). No `default_scope`. All mutations that will happen in later specs go through services; this plan adds only the `Events::Emit` service.

**Tech Stack:** Rails 8.1.3, Postgres, RSpec, `standardrb`, Solid trio already wired from Spec 01.

---

## Reconciliation notes (spec vs. current code)

Discrepancies between Spec 02 and the code as it exists after Spec 01:

1. **Users table column is `email_address`, not `email`.** Rails 8 auth generator produced `email_address` + `password_digest`. Spec 02 §2.2 says "`email` presence / uniqueness". **Plan decision:** keep the real column name `email_address`. The spec's intent is the column that stores the login email — that is `email_address`. Do not rename.
2. **`Current` already has `:session`** and delegates `:user`. Spec 02 §2.4 says `attribute :user`. **Plan decision:** add `attribute :user` alongside the existing `:session` attribute. Services use `Current.user` directly; controllers continue to set `Current.session`. The delegation can stay but `Current.user=` becomes an explicit setter for jobs/background paths.
3. **`User#has_secure_password`** already present. Don't re-add.

---

## Files to touch

### Create — migrations (`packages/app/db/migrate/`)

Timestamps use `YYYYMMDDHHMMSS`; generate with `bin/rails generate migration`. Final order/prefix decided at generation time — keep this ordering:

1. `ExtendUsers` — add `name`, `role`, `availability` + check constraints
2. `CreateTeams`
3. `CreateTeamMembers`
4. `CreateChannels`
5. `CreateChannelTeams`
6. `CreateContacts`
7. `CreateContactChannels`
8. `CreateConversations`
9. `CreateMessages`
10. `CreateAutomationRules`
11. `CreateEvents`
12. Active Storage install (`bin/rails active_storage:install`)

### Create — models (`packages/app/app/models/`)

- `team.rb`, `team_member.rb`
- `channel.rb`, `channel_team.rb`
- `contact.rb`, `contact_channel.rb`
- `conversation.rb`, `message.rb`
- `automation_rule.rb`, `event.rb`

### Modify — models

- `user.rb` — add `role` + `availability` enums, new associations, validation on `name`/`role`
- `current.rb` — add `attribute :user`

### Create — services (`packages/app/app/services/events/`)

- `packages/app/app/services/events/emit.rb`

### Modify — seeds

- `packages/app/db/seeds.rb` — idempotent dev dataset (users, teams, channels, channel_teams, contacts, contact_channels, conversations, messages)

### Create — specs (`packages/app/spec/`)

- `spec/models/user_spec.rb` (modify/create)
- `spec/models/team_spec.rb`
- `spec/models/team_member_spec.rb`
- `spec/models/channel_spec.rb`
- `spec/models/channel_team_spec.rb`
- `spec/models/contact_spec.rb`
- `spec/models/contact_channel_spec.rb`
- `spec/models/conversation_spec.rb`
- `spec/models/message_spec.rb`
- `spec/models/automation_rule_spec.rb`
- `spec/models/event_spec.rb`
- `spec/services/events/emit_spec.rb`
- `spec/support/` — add `shoulda-matchers` initializer (see Task A.0)

### Gemfile

**No new gems.** Per CLAUDE.md "You want to add a gem. Don't, unless the spec explicitly called for it." Spec 02 does not call for `shoulda-matchers` or `factory_bot_rails`. All model specs are plain RSpec:
- Associations: instantiate both sides, assert `record.assoc` returns the expected collection/object.
- Validations: build a record with the bad attribute, assert `record.valid?` is false and `record.errors[:attr]` is non-empty.
- Enums: assert `Model.<enum>.keys == %w[...]`.
- DB check constraints: call `record.update_columns(col: "bogus")` (bypasses validations), then `record.reload` + expect DB error on subsequent save, or run `expect { Model.connection.execute("INSERT ...") }.to raise_error(ActiveRecord::StatementInvalid)`.
- Encrypted credentials: `expect(Channel.connection.execute("SELECT credentials FROM channels WHERE id = #{c.id}").first["credentials"]).not_to include("plaintext-secret")`.

Fixtures: inline literal records inside each `it` block, or a minimal `let` block at the top of each spec. No FactoryBot.

### Modify — `db/schema.rb`

Auto-generated on `db:migrate`. Do not hand-edit.

---

## Test catalogue

Test names are specifications. Full RSpec `describe`/`it` blocks.

### `spec/models/user_spec.rb`

- `it validates presence of name`
- `it validates presence of role`
- `it validates presence of email_address`
- `it enforces uniqueness of email_address (case-insensitive)`
- `it defines role enum with admin, supervisor, agent values`
- `it defines availability enum with online, busy, offline values`
- `it defaults availability to offline`
- `it has many team_members`
- `it has many teams through team_members`
- `it has many assigned_conversations with foreign_key assignee_id`
- `it rejects invalid role at the DB level via check constraint`

### `spec/models/team_spec.rb`

- `it validates presence of name`
- `it has many team_members`
- `it has many users through team_members`
- `it has many channel_teams`
- `it has many channels through channel_teams`
- `it has many conversations with dependent: :restrict_with_error`

### `spec/models/team_member_spec.rb`

- `it belongs to team`
- `it belongs to user`
- `it enforces uniqueness of (team_id, user_id)`

### `spec/models/channel_spec.rb`

- `it validates presence of channel_type, identifier, name`
- `it defines channel_type enum with whatsapp_cloud, zapi, evolution, instagram, telegram`
- `it enforces uniqueness of identifier scoped to channel_type`
- `it encrypts credentials at rest (ActiveRecord::Encryption)`
- `it has many channel_teams and teams through channel_teams`
- `it has many contact_channels, conversations`
- `it defaults active to true, auto_assign to false, greeting_enabled to false`
- `it rejects invalid channel_type at the DB level via check constraint`

### `spec/models/channel_team_spec.rb`

- `it belongs to channel`
- `it belongs to team`
- `it enforces uniqueness of (channel_id, team_id)`

### `spec/models/contact_spec.rb`

- `it has many contact_channels`
- `it has many channels through contact_channels`
- `it has many conversations`
- `it allows blank name/email/phone_number/identifier` (contacts may be anonymous at first contact)

### `spec/models/contact_channel_spec.rb`

- `it belongs to contact`
- `it belongs to channel`
- `it validates presence of source_id`
- `it enforces uniqueness of source_id scoped to channel_id`

### `spec/models/conversation_spec.rb`

- `it validates presence of display_id`
- `it enforces uniqueness of display_id`
- **Note on `display_id`:** Generation with Postgres advisory lock (Spec 02 §7.1) is deferred to the Ingestion spec (Spec 04). In this plan, `Conversation` spec and seeds pass `display_id:` explicitly. Creating a Conversation without `display_id` must fail validation.
- `it defines status enum with bot, queued, assigned, resolved`
- `it defaults status to bot`
- `it belongs to channel, contact, contact_channel`
- `it belongs to assignee (User) optionally`
- `it belongs to team optionally`
- `it has many messages`
- `it enforces partial unique index: only one open conversation per contact_channel when status != resolved`
- `it rejects invalid status at the DB level via check constraint`

### `spec/models/message_spec.rb`

- `it belongs to conversation, channel`
- `it has many_attached :attachments`
- `it defines direction enum with inbound, outbound`
- `it defines content_type enum with text, image, audio, video, document, location, contact_card, input_select, button_reply, template`
- `it defines status enum with received, pending, sent, delivered, read, failed`
- `it defaults content_type to text, status to received`
- `#sender returns the User when sender_type is User`
- `#sender returns the Contact when sender_type is Contact`
- `#sender returns nil when sender_type is Bot`
- `#sender returns nil when sender_type is System`
- `it rejects invalid direction/content_type/status at the DB level via check constraints`
- `it enforces partial unique index on (channel_id, external_id) when external_id is present`

### `spec/models/automation_rule_spec.rb`

- `it validates presence of event_name`
- `it defaults conditions to [], actions to [], active to true`

### `spec/models/event_spec.rb`

- `it validates presence of name, subject_type, subject_id`
- `it belongs to subject polymorphically`
- `it belongs to actor polymorphically, optional`
- `it has no updated_at column (immutable)`
- `it can be created via Event.create! with a Conversation subject and a User actor`
- `it can be created with an actor of nil (system events)`

### `spec/services/events/emit_spec.rb`

- `it creates an Event with a User actor`
- `it creates an Event with a Contact actor`
- `it creates an Event with actor: :system (sets actor_type/actor_id to nil)`
- `it creates an Event with actor: :bot (sets actor_type/actor_id to nil)`
- `it creates an Event with no actor (defaults to Current.user if set, else nil)`
- `it raises ActiveRecord::RecordInvalid when subject is nil`
- `it raises ArgumentError when name is blank`
- `it returns the created Event`
- `it stores payload verbatim`

### Migration round-trip

- `spec/db/migrations_roundtrip_spec.rb` — `rake db:rollback STEP=<N>` + `rake db:migrate` round-trip, asserting schema identity via `ActiveRecord::Base.connection.tables` before/after. *(Alternative: do this as a shell step in CI rather than a spec. Plan decision: shell step in CI, documented below under VERIFY.)*

### Test types required

- **Unit:** all model specs + `Events::Emit` service spec. **Mandatory.**
- **Integration:** `Events::Emit` spec exercises real DB writes + polymorphic associations end-to-end. Counts as an integration test.
- **E2E:** none in this plan — no dashboard views added here. Future specs (assignment, workspace) carry the Playwright coverage.

---

## Order of operations

Strict TDD: test first, watch it fail, implement, watch it pass, commit. Parallelization is done **per-model** in phase B once the foundation in phase A is green. Each subagent owns one model end-to-end (migration + model + spec + factory).

### Phase A — Foundation (sequential)

A.0. Create the feature branch `spec-02-core-domain-models` from `main`. Push. No code yet.

A.1. `ExtendUsers` migration (add `name`, `role`, `availability` + check constraints). Update `User` model (enums, validations). Update `spec/models/user_spec.rb`. Migrate. Run user spec. Green. `bin/standardrb --fix`. Commit `feat: extend users with role + availability`.

A.2. `bin/rails active_storage:install && bin/rails db:migrate`. Commit `chore: install Active Storage`.

A.3. **Human-gated:** run `bin/rails db:encryption:init`, add its output to `config/credentials.yml.enc`, commit the updated encrypted credentials file. This unblocks B.3.

### Phase B — Standalone tables (parallel, one subagent per card)

Each card = migration + model + factory + spec, committed on its own. **All independent of each other — dispatch in parallel.** Subagents must pull latest `main` of the branch after each prior merge.

- **B.1** `CreateTeams` + `Team` model + factory + `team_spec.rb`
- **B.2** `CreateTeamMembers` + `TeamMember` model + factory + `team_member_spec.rb` *(depends on B.1 being merged first)*
- **B.3** `CreateChannels` + `Channel` model (with `encrypts :credentials`) + `channel_spec.rb`. **Prerequisite:** A.3 (encryption keys) must be done first. The `encrypts credentials at rest` spec reads the raw column value and asserts it is not equal to the plain JSON — if keys are missing, this test fails loudly.
- **B.4** `CreateChannelTeams` + `ChannelTeam` model + factory + `channel_team_spec.rb` *(depends on B.1 + B.3)*
- **B.5** `CreateContacts` + `Contact` model + factory + `contact_spec.rb`
- **B.6** `CreateContactChannels` + `ContactChannel` model + factory + `contact_channel_spec.rb` *(depends on B.3 + B.5)*
- **B.7** `CreateAutomationRules` + `AutomationRule` model + factory + `automation_rule_spec.rb`
- **B.8** `CreateEvents` + `Event` model + factory + `event_spec.rb` (polymorphic associations, immutability)

Dispatch strategy: B.1, B.3, B.5, B.7, B.8 in **parallel wave 1** (independent). Wave 2 (B.2, B.4, B.6) after wave 1 merges.

### Phase C — Dependent tables (sequential after Phase B)

- **C.1** `CreateConversations` + `Conversation` model + factory + `conversation_spec.rb` (depends on B.3, B.5, B.6)
- **C.2** `CreateMessages` + `Message` model (`#sender` method + `has_many_attached`) + factory + `message_spec.rb` (depends on C.1)

### Phase D — Audit + context (parallel with C, no FK conflicts)

- **D.1** `Events::Emit` service + `spec/services/events/emit_spec.rb` — depends only on `Event` model (B.8).
- **D.2** `Current` — add `attribute :user`. One-line change + spec confirmation that `Current.user = u` works independently of `Current.session`.

### Phase E — Seeds + VERIFY

- **E.1** `db/seeds.rb` rewritten per Spec 02 §2.5. Idempotent via `find_or_create_by`. `bin/rails db:drop db:create db:migrate db:seed && bin/rails db:seed` (twice). Commit.
- **E.2** Full suite: `bundle exec rspec`, `bin/standardrb --fix`, migration round-trip (`bin/rails db:drop db:create db:migrate && bin/rails db:rollback STEP=12 && bin/rails db:migrate`). Fix anything that breaks.
- **E.3** Update `docs/PROGRESS.md`: Plan 02 → In Progress → Shipped on merge. Update `ARCHITECTURE.md` / `GLOSSARY.md` if any new term was introduced (should be none — all terms in the spec are already in the glossary).

---

## Subagent dispatch specification

For every card in Phases B, C, D: dispatch a fresh `general-purpose` subagent using `model: sonnet` with **low effort** guidance in the prompt (e.g. *"stay within the scope of this card; don't refactor adjacent code; no scope creep"*).

Each subagent brief must include:

1. The exact card number (e.g. `B.3 — Channels`)
2. The exact spec lines it implements (Spec 02 §2.1 migration N, §2.2 model row)
3. The test file path + test names from the catalogue above
4. TDD order: write spec → run → fail → write migration → migrate → write model → run → pass → standardrb → commit
5. Commit message convention: `feat: add <thing>` / `feat: add <thing> spec`
6. Hard rules: no touching unrelated files, no adding dependencies, no modifying `user.rb` beyond what the plan allows for Phase A
7. On completion: return the commit SHA and the RSpec output for the new spec file

Main session reviews each subagent's diff before moving to the next wave. If review finds drift, main session fixes it — does not re-dispatch.

---

## What could go wrong

**Most likely:** Enum check constraints + Rails `enum` declarations drift. If a migration defines `CHECK (role IN ('admin','supervisor','agent'))` and the model declares `enum role: { admin: "admin", supervisor: "supervisor", agent: "agent" }`, a typo breaks both in a correlated way that's easy to miss. Mitigation: each model spec has a "rejects invalid value at the DB level via check constraint" test that performs `update_columns(role: "bogus")` then reloads and triggers a save that violates the constraint. If the constraint is missing the test fails loudly.

**Second most likely:** `Conversation` partial unique index `(contact_channel_id) WHERE status != 'resolved'` interacts badly with Rails model-level uniqueness validations (which Rails cannot express as partial). The model does not need a uniqueness validator — only the DB constraint. The spec must test that the DB raises `ActiveRecord::RecordNotUnique`, not that the model's `valid?` returns false.

**Least likely:** ActiveRecord Encryption key setup fails silently and `channel.credentials` ends up stored in cleartext. Mitigation: `spec/models/channel_spec.rb` has an explicit "it encrypts credentials at rest" test that reads the raw column value via `Channel.connection.execute("SELECT credentials FROM channels ...")` and asserts it is not a plain JSON object.

---

## Rollback strategy

Every migration is reversible (`def change`, not `def up` + `def down` with data movement — there is no data in this plan). Migration round-trip verified in Phase E.2. If a single migration in Phase B fails partway, the whole branch is rebased against `main` and the affected card re-runs from a clean schema.

---

## Acceptance (from Spec 02)

All 9 acceptance criteria from Spec 02 §5 must pass at end of Phase E. CI green on PR is the final gate.
