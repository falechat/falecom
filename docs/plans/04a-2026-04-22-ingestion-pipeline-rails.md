# Plan 04a: Ingestion Pipeline — Rails Side

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> **Spec:** [04 — Ingestion Pipeline (v2 hardening)](../specs/04-ingestion-pipeline.md)
> **Date:** 2026-04-22
> **Status:** Draft — awaiting approval
> **Branch:** `plan-04a-ingestion-rails`

**Goal:** Ship the Rails half of the ingestion pipeline — `Internal::IngestController` plus `Ingestion::ProcessMessage` / `ProcessStatusUpdate` orchestrators and the `Contacts::Resolve` / `Conversations::ResolveOrCreate` / `Messages::Create` services, with the `rake ingest:mock` dev utility. After this plan, a channel container can POST a valid Common Ingestion Payload to `/internal/ingest` and end up with persisted `Contact`, `ContactChannel`, `Conversation`, `Message`, and `Event` rows plus a Turbo Stream broadcast. No channel container, no `dev-webhook`, no LocalStack — those land in Plan 04b.

**Architecture:** Pure Rails. `Internal::IngestController` validates the payload against `FaleComChannel::Payload.validate!` (path dep on the gem from Plan 03), performs the `Channel.find_by(channel_type:, identifier:)&.active?` lookup, routes by `payload["type"]`, and delegates to service orchestrators. All state changes happen inside a single transaction with inline `pg_advisory_xact_lock(hashtext('display_id'))` to serialize `display_id` generation. Idempotency at the DB layer via the existing `(channel_id, external_id)` unique partial index from Spec 02 — `Messages::Create` uses `insert_all` + `unique_by:` + a `#duplicate?` sentinel on the returned record so orchestrators can short-circuit.

**Tech Stack:** Ruby 4.0.2, Rails 8.1.3, RSpec 7.1, `standardrb`, `falecom_channel` gem (path dep — provides `Payload.validate!`), Solid Queue (already installed), Turbo Streams (already installed). No new gems.

---

## Files to touch

All paths relative to repo root. Every command runs inside the `falecom-workspace-1` container via `docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && …"`.

### Create — services

- `packages/app/app/services/messages/create.rb`
- `packages/app/app/services/contacts/resolve.rb`
- `packages/app/app/services/conversations/resolve_or_create.rb`
- `packages/app/app/services/ingestion/process_message.rb`
- `packages/app/app/services/ingestion/process_status_update.rb`

### Create — controller

- `packages/app/app/controllers/internal/ingest_controller.rb`

### Create — rake task

- `packages/app/lib/tasks/ingest.rake`

### Create — specs

- `packages/app/spec/services/messages/create_spec.rb`
- `packages/app/spec/services/contacts/resolve_spec.rb`
- `packages/app/spec/services/conversations/resolve_or_create_spec.rb`
- `packages/app/spec/services/ingestion/process_message_spec.rb`
- `packages/app/spec/services/ingestion/process_status_update_spec.rb`
- `packages/app/spec/requests/internal/ingest_spec.rb`
- `packages/app/spec/tasks/ingest_spec.rb`
- `packages/app/spec/support/payload_fixtures.rb` — canonical Common Ingestion Payload hashes reused across request + orchestrator specs

### Modify

- `packages/app/Gemfile` — add `gem "falecom_channel", path: "../falecom_channel"`
- `packages/app/config/routes.rb` — add `namespace :internal { post "ingest", to: "ingest#create" }`
- `packages/app/spec/rails_helper.rb` — `require "falecom_channel"` so the gem is loaded before specs

---

## Order of operations (TDD wave)

1. Foundation (Gemfile, routes, rails_helper) — smallest diff that gets the gem loadable in tests.
2. `Messages::Create` — bottommost service, no collaborators except `Events::Emit` + DB.
3. `Contacts::Resolve` — depends on DB only.
4. `Conversations::ResolveOrCreate` — depends on DB + advisory lock.
5. `Ingestion::ProcessMessage` — orchestrates 2 + 3 + 4 + broadcast.
6. `Ingestion::ProcessStatusUpdate` — standalone, depends on Message model.
7. `Internal::IngestController` — request spec + controller routes to orchestrators.
8. `rake ingest:mock` — drives `Ingestion::ProcessMessage` directly for dev smoke.
9. Regression sweep — full `packages/app` + `packages/falecom_channel` rspec + standardrb.

Each task ends with a commit. Keep commits small and named with Conventional Commits prefixes (`feat`, `fix`, `test`, `chore`, `docs`).

---

## What could go wrong

**Most likely:** the `falecom_channel` path dep adds load-order complexity. The gem uses `dry-struct` + `dry-validation` and has its own `Gemfile`; adding it as a path dep in the app drags those transitive deps into the app's `Gemfile.lock`. Mitigation: run `bundle install` after the Gemfile edit and let Bundler resolve; if any conflict surfaces, pin `dry-*` explicitly in the app Gemfile to the same majors the gem uses.

**Least likely:** the advisory-lock approach deadlocks two concurrent ingests. It shouldn't — all callers take the lock on the same key + the lock is transaction-scoped, so it releases on commit/rollback. If it does, the last-line-of-defense partial unique index on `conversations(contact_channel_id) WHERE status <> 'resolved'` will surface the race as `PG::UniqueViolation`, which the orchestrator re-runs once on catch. Tested in Task 4.

---

## Task 1: Foundation — gem path dep + route + rails_helper

**Files:**
- Modify: `packages/app/Gemfile`
- Modify: `packages/app/config/routes.rb`
- Modify: `packages/app/spec/rails_helper.rb`

- [ ] **Step 1: Add `falecom_channel` path dep to `Gemfile`**

Append inside the main group (above the `:development, :test` group block):

```ruby
# Shared channel-container gem. Path dep in this monorepo.
# Used here for FaleComChannel::Payload.validate!.
gem "falecom_channel", path: "../falecom_channel"
```

- [ ] **Step 2: Run `bundle install`**

Run:
```
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && bundle install"
```
Expected: adds `falecom_channel (0.1.0)` plus transitive `dry-struct`, `dry-validation`, etc. No conflict errors.

- [ ] **Step 3: Add internal ingest route**

Edit `packages/app/config/routes.rb`. Replace the single existing `Rails.application.routes.draw do … end` block by adding the namespace inside it. Before:

```ruby
Rails.application.routes.draw do
  root "dashboard#show"

  resource :session
  resources :passwords, param: :token
  # …
end
```

After (add only the `namespace` block; keep everything else):

```ruby
Rails.application.routes.draw do
  root "dashboard#show"

  resource :session
  resources :passwords, param: :token

  namespace :internal do
    post "ingest", to: "ingest#create"
  end

  # …
end
```

- [ ] **Step 4: Require the gem in rails_helper**

Edit `packages/app/spec/rails_helper.rb`. Add `require "falecom_channel"` after the existing `require "rspec/rails"` line. Example:

```ruby
require "rspec/rails"
require "falecom_channel"
```

- [ ] **Step 5: Run existing spec suite to confirm no regression**

Run (remember: unset `DATABASE_URL` — workspace default points at dev DB):
```
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && unset DATABASE_URL && bundle exec rspec"
```
Expected: all existing examples pass (from Spec 02), no new failures from the Gemfile change.

- [ ] **Step 6: Commit**

```
git add packages/app/Gemfile packages/app/Gemfile.lock packages/app/config/routes.rb packages/app/spec/rails_helper.rb
git commit -m "chore(app): add falecom_channel path dep, internal/ingest route, rails_helper require"
```

---

## Task 2: `Messages::Create` service (kwargs, `#duplicate?` sentinel)

**Files:**
- Create: `packages/app/app/services/messages/create.rb`
- Create: `packages/app/spec/services/messages/create_spec.rb`

- [ ] **Step 1: Write the failing spec**

Create `packages/app/spec/services/messages/create_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Messages::Create do
  let(:channel) do
    Channel.create!(
      channel_type: "whatsapp_cloud",
      identifier:   "+5511999999999",
      name:         "WhatsApp Sales"
    )
  end
  let(:contact) { Contact.create!(name: "João") }
  let(:contact_channel) do
    ContactChannel.create!(channel: channel, contact: contact, source_id: "5511988888888")
  end
  let(:conversation) do
    channel.conversations.create!(
      contact:          contact,
      contact_channel:  contact_channel,
      status:           "queued",
      display_id:       1,
      last_activity_at: Time.current
    )
  end

  let(:base_kwargs) do
    {
      conversation: conversation,
      direction:    "inbound",
      content:      "Olá",
      content_type: "text",
      status:       "received",
      sender:       contact,
      external_id:  "WAMID.ABC",
      sent_at:      Time.current
    }
  end

  it "inserts a Message with the provided attrs and returns it with #duplicate? == false" do
    message = described_class.call(**base_kwargs)

    expect(message).to be_persisted
    expect(message.channel_id).to eq(channel.id)
    expect(message.conversation_id).to eq(conversation.id)
    expect(message.direction).to eq("inbound")
    expect(message.external_id).to eq("WAMID.ABC")
    expect(message.status).to eq("received")
    expect(message.sender).to eq(contact)
    expect(message.duplicate?).to eq(false)
  end

  it "bumps conversation.last_activity_at" do
    before = 1.day.ago
    conversation.update!(last_activity_at: before)

    described_class.call(**base_kwargs)

    expect(conversation.reload.last_activity_at).to be > before
  end

  it "emits messages:inbound when direction == 'inbound'" do
    expect {
      described_class.call(**base_kwargs)
    }.to change { Event.where(name: "messages:inbound").count }.by(1)
  end

  it "emits messages:outbound when direction == 'outbound'" do
    expect {
      described_class.call(**base_kwargs.merge(direction: "outbound", status: "pending"))
    }.to change { Event.where(name: "messages:outbound").count }.by(1)
  end

  it "returns the existing record with #duplicate? == true on (channel_id, external_id) collision" do
    first  = described_class.call(**base_kwargs)
    second = described_class.call(**base_kwargs.merge(content: "DUPLICATE"))

    expect(second.id).to eq(first.id)
    expect(second.content).to eq("Olá")
    expect(second.duplicate?).to eq(true)
    expect(Message.where(external_id: "WAMID.ABC").count).to eq(1)
  end

  it "emits no event on duplicate" do
    described_class.call(**base_kwargs)

    expect {
      described_class.call(**base_kwargs)
    }.not_to change { Event.count }
  end

  it "inserts without external_id when none given (system message path)" do
    message = described_class.call(
      conversation: conversation,
      direction:    "outbound",
      content:      "Transferência interna",
      content_type: "text",
      status:       "received",
      sender:       nil
    )

    expect(message).to be_persisted
    expect(message.external_id).to be_nil
    expect(message.sender).to be_nil
    expect(message.duplicate?).to eq(false)
  end
end
```

- [ ] **Step 2: Run it — expect NameError**

```
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && unset DATABASE_URL && bundle exec rspec spec/services/messages/create_spec.rb"
```
Expected: `NameError: uninitialized constant Messages::Create`.

- [ ] **Step 3: Implement the service**

Create `packages/app/app/services/messages/create.rb`:

```ruby
module Messages
  # Single entry point for every Message creation. Kwargs-based so inbound,
  # outbound, bot, and system callers share one API.
  #
  # Returns a Message decorated with a #duplicate? method:
  #   - false if this call inserted the row
  #   - true  if an existing row with the same (channel_id, external_id)
  #           was found (via ON CONFLICT); caller should skip broadcast
  #           + event emission.
  class Create
    def self.call(conversation:, direction:, content:, content_type:, status:,
      sender: nil, external_id: nil, reply_to_external_id: nil, sent_at: nil,
      metadata: {}, raw: nil)
      attrs = {
        channel_id: conversation.channel_id,
        conversation_id: conversation.id,
        direction: direction,
        content: content,
        content_type: content_type,
        status: status,
        sender_type: sender&.class&.base_class&.name,
        sender_id: sender&.id,
        external_id: external_id,
        reply_to_external_id: reply_to_external_id,
        sent_at: sent_at,
        metadata: metadata.to_h,
        raw: raw
      }

      message = if external_id.present?
        insert_with_conflict(attrs, conversation: conversation, external_id: external_id)
      else
        attach_duplicate_flag(Message.create!(attrs), false)
      end

      return message if message.duplicate?

      conversation.update!(last_activity_at: Time.current)
      emit_event(message, direction, sender)
      message
    end

    def self.insert_with_conflict(attrs, conversation:, external_id:)
      now = Time.current
      result = Message.insert_all(
        [attrs.merge(created_at: now, updated_at: now)],
        returning: [:id],
        unique_by: :index_messages_on_channel_id_and_external_id
      )

      if result.rows.empty?
        existing = Message.find_by!(
          channel_id: conversation.channel_id,
          external_id: external_id
        )
        attach_duplicate_flag(existing, true)
      else
        attach_duplicate_flag(Message.find(result.rows.first.first), false)
      end
    end

    def self.attach_duplicate_flag(message, value)
      message.define_singleton_method(:duplicate?) { value }
      message
    end

    def self.emit_event(message, direction, sender)
      name = (direction == "inbound") ? "messages:inbound" : "messages:outbound"
      Events::Emit.call(name: name, subject: message, actor: sender || :system)
    end

    private_class_method :insert_with_conflict, :attach_duplicate_flag, :emit_event
  end
end
```

- [ ] **Step 4: Run the spec — expect all green**

```
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && unset DATABASE_URL && bundle exec rspec spec/services/messages/create_spec.rb"
```
Expected: 7 examples, 0 failures.

- [ ] **Step 5: Run standardrb + fix auto-correctable issues**

```
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && bundle exec standardrb --fix"
```
Expected: clean (or auto-fixed).

- [ ] **Step 6: Commit**

```
git add packages/app/app/services/messages/create.rb packages/app/spec/services/messages/create_spec.rb
git commit -m "feat(app): add Messages::Create service with kwargs + duplicate? sentinel"
```

---

## Task 3: `Contacts::Resolve` service

**Files:**
- Create: `packages/app/app/services/contacts/resolve.rb`
- Create: `packages/app/spec/services/contacts/resolve_spec.rb`

- [ ] **Step 1: Write the failing spec**

Create `packages/app/spec/services/contacts/resolve_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Contacts::Resolve do
  let(:channel) do
    Channel.create!(channel_type: "whatsapp_cloud", identifier: "+5511999999999", name: "WhatsApp Sales")
  end

  describe ".call" do
    context "brand new (channel, source_id)" do
      let(:contact_data) do
        {"source_id" => "5511988888888", "name" => "João", "phone_number" => "+5511988888888"}
      end

      it "creates a Contact and a ContactChannel" do
        expect {
          described_class.call(channel, contact_data)
        }.to change { Contact.count }.by(1)
          .and change { ContactChannel.count }.by(1)
      end

      it "returns [contact, contact_channel]" do
        contact, contact_channel = described_class.call(channel, contact_data)

        expect(contact).to be_a(Contact)
        expect(contact_channel).to be_a(ContactChannel)
        expect(contact_channel.contact).to eq(contact)
        expect(contact_channel.channel).to eq(channel)
        expect(contact_channel.source_id).to eq("5511988888888")
      end

      it "emits contacts:created and contact_channels:created" do
        expect {
          described_class.call(channel, contact_data)
        }.to change { Event.where(name: "contacts:created").count }.by(1)
          .and change { Event.where(name: "contact_channels:created").count }.by(1)
      end
    end

    context "phone_number already matches an existing Contact" do
      let!(:existing_contact) { Contact.create!(name: "João Old", phone_number: "+5511988888888") }

      it "reuses the existing Contact, links a new ContactChannel" do
        contact, contact_channel = described_class.call(
          channel,
          {"source_id" => "5511988888888", "name" => "João", "phone_number" => "+5511988888888"}
        )

        expect(contact.id).to eq(existing_contact.id)
        expect(contact_channel.contact_id).to eq(existing_contact.id)
      end

      it "does NOT emit contacts:created (only contact_channels:created)" do
        expect {
          described_class.call(
            channel,
            {"source_id" => "5511988888888", "phone_number" => "+5511988888888"}
          )
        }.to change { Event.where(name: "contacts:created").count }.by(0)
          .and change { Event.where(name: "contact_channels:created").count }.by(1)
      end
    end

    context "existing (channel, source_id)" do
      let!(:contact) { Contact.create!(name: "João", phone_number: "+5511988888888") }
      let!(:contact_channel) do
        ContactChannel.create!(channel: channel, contact: contact, source_id: "5511988888888")
      end

      it "returns the existing pair without creating new records" do
        expect {
          described_class.call(channel, {"source_id" => "5511988888888", "name" => "João"})
        }.to change { Contact.count }.by(0)
          .and change { ContactChannel.count }.by(0)
      end

      it "emits nothing on re-resolve with identical data" do
        expect {
          described_class.call(channel, {"source_id" => "5511988888888", "name" => "João"})
        }.to change { Event.count }.by(0)
      end

      it "merges blank-to-populated fields but does not overwrite existing non-blank values" do
        described_class.call(
          channel,
          {
            "source_id" => "5511988888888",
            "name" => "OVERWRITE ATTEMPT",
            "email" => "joao@example.com"
          }
        )

        contact.reload
        expect(contact.name).to eq("João")                    # preserved
        expect(contact.email).to eq("joao@example.com")       # filled
      end
    end
  end
end
```

- [ ] **Step 2: Run it — expect NameError**

```
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && unset DATABASE_URL && bundle exec rspec spec/services/contacts/resolve_spec.rb"
```
Expected: `NameError: uninitialized constant Contacts::Resolve`.

- [ ] **Step 3: Implement the service**

Create `packages/app/app/services/contacts/resolve.rb`:

```ruby
module Contacts
  # Resolves (or creates) a Contact + ContactChannel pair for an inbound
  # payload's `contact` section.
  #
  # Two paths:
  #   1. Exact match on (channel, source_id) → return existing; merge non-blank fields.
  #   2. No match → universal dedup on phone_number or email; reuse that Contact
  #      if present, else create a new one. Link a fresh ContactChannel either way.
  #
  # Cross-instance match (same source_id on other channels of same type) is
  # out of scope for Plan 04 — deferred per Spec 04 v2 § Out of scope.
  class Resolve
    MERGEABLE_FIELDS = %w[name phone_number email avatar_url].freeze

    def self.call(channel, contact_data)
      contact_channel = ContactChannel.find_or_initialize_by(
        channel: channel,
        source_id: contact_data.fetch("source_id")
      )

      if contact_channel.new_record?
        create_path(channel, contact_channel, contact_data)
      else
        reuse_path(contact_channel, contact_data)
      end
    end

    def self.create_path(_channel, contact_channel, contact_data)
      contact = find_existing_contact(contact_data) || Contact.create!(
        name: contact_data["name"],
        phone_number: contact_data["phone_number"],
        email: contact_data["email"]
      )

      contact_channel.contact = contact
      contact_channel.save!

      Events::Emit.call(name: "contacts:created", subject: contact, actor: :system) if contact.previously_new_record?
      Events::Emit.call(name: "contact_channels:created", subject: contact_channel, actor: :system)

      [contact, contact_channel]
    end

    def self.reuse_path(contact_channel, contact_data)
      contact = contact_channel.contact
      merge_contact_fields!(contact, contact_data)
      [contact, contact_channel]
    end

    def self.find_existing_contact(contact_data)
      if contact_data["phone_number"].present?
        hit = Contact.find_by(phone_number: contact_data["phone_number"])
        return hit if hit
      end
      if contact_data["email"].present?
        return Contact.find_by(email: contact_data["email"])
      end
      nil
    end

    # Provider-reported data never overwrites an existing non-blank field.
    # Two exceptions (applied via other code paths, not this helper):
    #   - Bot-collected values in Flows::Handoff (Spec 07).
    #   - Manual agent edits in the dashboard (Spec 06).
    def self.merge_contact_fields!(contact, contact_data)
      updates = {}
      MERGEABLE_FIELDS.each do |field|
        incoming = contact_data[field]
        next if incoming.blank?
        next if contact.public_send(field).present?
        updates[field] = incoming
      end
      contact.update!(updates) if updates.any?
    end

    private_class_method :create_path, :reuse_path, :find_existing_contact, :merge_contact_fields!
  end
end
```

- [ ] **Step 4: Run the spec — expect all green**

```
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && unset DATABASE_URL && bundle exec rspec spec/services/contacts/resolve_spec.rb"
```
Expected: 9 examples, 0 failures.

- [ ] **Step 5: standardrb**

```
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && bundle exec standardrb --fix"
```

- [ ] **Step 6: Commit**

```
git add packages/app/app/services/contacts/resolve.rb packages/app/spec/services/contacts/resolve_spec.rb
git commit -m "feat(app): add Contacts::Resolve with exact + universal (phone/email) dedup"
```

---

## Task 4: `Conversations::ResolveOrCreate` service (advisory lock)

**Files:**
- Create: `packages/app/app/services/conversations/resolve_or_create.rb`
- Create: `packages/app/spec/services/conversations/resolve_or_create_spec.rb`

- [ ] **Step 1: Write the failing spec**

Create `packages/app/spec/services/conversations/resolve_or_create_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Conversations::ResolveOrCreate do
  let(:channel) do
    Channel.create!(channel_type: "whatsapp_cloud", identifier: "+5511999999999", name: "WhatsApp Sales")
  end
  let(:contact) { Contact.create!(name: "João") }
  let(:contact_channel) do
    ContactChannel.create!(channel: channel, contact: contact, source_id: "5511988888888")
  end

  describe ".call" do
    context "no conversations exist for this contact_channel" do
      it "creates a new conversation with status queued when the channel has no active flow" do
        conversation = described_class.call(channel, contact, contact_channel)

        expect(conversation).to be_persisted
        expect(conversation.status).to eq("queued")
        expect(conversation.display_id).to eq(1)
        expect(conversation.last_activity_at).to be_within(2.seconds).of(Time.current)
      end

      it "creates it with status bot when the channel has an active_flow_id" do
        channel.update!(active_flow_id: 1) # placeholder — FK not enforced until Spec 07 migration
        conversation = described_class.call(channel, contact, contact_channel)
        expect(conversation.status).to eq("bot")
      end

      it "emits conversations:created" do
        expect {
          described_class.call(channel, contact, contact_channel)
        }.to change { Event.where(name: "conversations:created").count }.by(1)
      end
    end

    context "an open conversation already exists for this contact_channel" do
      let!(:open_conversation) do
        channel.conversations.create!(
          contact: contact,
          contact_channel: contact_channel,
          status: "assigned",
          display_id: 7,
          last_activity_at: 1.hour.ago
        )
      end

      it "returns the existing open conversation" do
        conversation = described_class.call(channel, contact, contact_channel)
        expect(conversation.id).to eq(open_conversation.id)
      end

      it "emits no new conversations:created event" do
        expect {
          described_class.call(channel, contact, contact_channel)
        }.to change { Event.where(name: "conversations:created").count }.by(0)
      end
    end

    context "only resolved conversations exist" do
      before do
        channel.conversations.create!(
          contact: contact,
          contact_channel: contact_channel,
          status: "resolved",
          display_id: 3,
          last_activity_at: 1.day.ago
        )
      end

      it "creates a new conversation with the next display_id" do
        conversation = described_class.call(channel, contact, contact_channel)
        expect(conversation).to be_persisted
        expect(conversation.display_id).to eq(4)
      end
    end

    describe "display_id generation under concurrency" do
      it "serializes display_id assignment via an advisory lock (no duplicate display_ids)" do
        contact_b = Contact.create!(name: "Maria")
        contact_channel_b = ContactChannel.create!(channel: channel, contact: contact_b, source_id: "5511977777777")

        results = []
        threads = [
          Thread.new { ActiveRecord::Base.connection_pool.with_connection { results << described_class.call(channel, contact, contact_channel) } },
          Thread.new { ActiveRecord::Base.connection_pool.with_connection { results << described_class.call(channel, contact_b, contact_channel_b) } }
        ]
        threads.each(&:join)

        display_ids = results.map(&:display_id)
        expect(display_ids.sort).to eq([1, 2])
      end
    end
  end
end
```

- [ ] **Step 2: Run it — expect NameError**

```
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && unset DATABASE_URL && bundle exec rspec spec/services/conversations/resolve_or_create_spec.rb"
```
Expected: `NameError: uninitialized constant Conversations::ResolveOrCreate`.

- [ ] **Step 3: Implement the service**

Create `packages/app/app/services/conversations/resolve_or_create.rb`:

```ruby
module Conversations
  # Returns the open Conversation for (channel, contact_channel) or creates one.
  #
  # display_id assignment is serialized with a transaction-scoped Postgres
  # advisory lock keyed on hashtext('display_id'). No `with_advisory_lock` gem
  # dependency; the lock auto-releases on commit/rollback.
  class ResolveOrCreate
    def self.call(channel, contact, contact_channel)
      ActiveRecord::Base.transaction do
        ActiveRecord::Base.connection.execute(
          "SELECT pg_advisory_xact_lock(hashtext('display_id'))"
        )

        open = channel.conversations
          .where(contact_channel: contact_channel)
          .where.not(status: "resolved")
          .order(created_at: :desc)
          .first
        return open if open

        conversation = channel.conversations.create!(
          contact: contact,
          contact_channel: contact_channel,
          status: channel.active_flow_id? ? "bot" : "queued",
          display_id: next_display_id,
          last_activity_at: Time.current
        )

        Events::Emit.call(
          name: "conversations:created",
          subject: conversation,
          actor: :system
        )

        conversation
      end
    end

    def self.next_display_id
      (Conversation.maximum(:display_id) || 0) + 1
    end

    private_class_method :next_display_id
  end
end
```

- [ ] **Step 4: Run the spec — expect all green**

```
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && unset DATABASE_URL && bundle exec rspec spec/services/conversations/resolve_or_create_spec.rb"
```
Expected: 6 examples, 0 failures.

- [ ] **Step 5: standardrb + commit**

```
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && bundle exec standardrb --fix"
git add packages/app/app/services/conversations/resolve_or_create.rb packages/app/spec/services/conversations/resolve_or_create_spec.rb
git commit -m "feat(app): add Conversations::ResolveOrCreate with pg_advisory_xact_lock display_id"
```

---

## Task 5: `Ingestion::ProcessMessage` orchestrator + payload fixtures

**Files:**
- Create: `packages/app/spec/support/payload_fixtures.rb`
- Create: `packages/app/app/services/ingestion/process_message.rb`
- Create: `packages/app/spec/services/ingestion/process_message_spec.rb`
- Modify: `packages/app/spec/rails_helper.rb` — require support files

- [ ] **Step 1: Add the payload fixtures helper**

Create `packages/app/spec/support/payload_fixtures.rb`:

```ruby
module PayloadFixtures
  module_function

  def inbound_text(overrides = {})
    {
      "type" => "inbound_message",
      "channel" => {"type" => "whatsapp_cloud", "identifier" => "+5511999999999"},
      "contact" => {
        "source_id" => "5511988888888",
        "name" => "João Silva",
        "phone_number" => "+5511988888888",
        "email" => nil,
        "avatar_url" => nil
      },
      "message" => {
        "external_id" => "WAMID.HBgL#{SecureRandom.hex(6)}",
        "direction" => "inbound",
        "content" => "Olá, gostaria de saber mais sobre o produto.",
        "content_type" => "text",
        "attachments" => [],
        "sent_at" => "2026-04-22T12:00:00Z",
        "reply_to_external_id" => nil
      },
      "metadata" => {
        "whatsapp_context" => {"business_account_id" => "123", "phone_number_id" => "456"}
      },
      "raw" => {"original" => "meta payload bytes would live here"}
    }.deep_merge(overrides)
  end

  def status_update(overrides = {})
    {
      "type" => "outbound_status_update",
      "channel" => {"type" => "whatsapp_cloud", "identifier" => "+5511999999999"},
      "external_id" => "WAMID.HBgL_ABC",
      "status" => "delivered",
      "timestamp" => "2026-04-22T12:05:00Z",
      "error" => nil,
      "metadata" => {}
    }.deep_merge(overrides)
  end
end
```

- [ ] **Step 2: Load support files from rails_helper**

Edit `packages/app/spec/rails_helper.rb`. After the `require "falecom_channel"` line, add:

```ruby
Dir[Rails.root.join("spec", "support", "**", "*.rb")].each { |f| require f }
```

- [ ] **Step 3: Write the failing spec**

Create `packages/app/spec/services/ingestion/process_message_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Ingestion::ProcessMessage do
  let(:channel) do
    Channel.create!(
      channel_type: "whatsapp_cloud",
      identifier: "+5511999999999",
      name: "WhatsApp Sales"
    )
  end

  describe ".call" do
    it "creates Contact, ContactChannel, Conversation, and Message and emits expected events" do
      payload = PayloadFixtures.inbound_text

      expect {
        described_class.call(channel, payload)
      }.to change { Contact.count }.by(1)
        .and change { ContactChannel.count }.by(1)
        .and change { Conversation.count }.by(1)
        .and change { Message.count }.by(1)

      names = Event.pluck(:name)
      expect(names).to include("contacts:created", "contact_channels:created", "conversations:created", "messages:inbound")
    end

    it "is idempotent on the same external_id — second call creates no new records and emits no new events" do
      payload = PayloadFixtures.inbound_text

      described_class.call(channel, payload)

      expect {
        described_class.call(channel, payload)
      }.to change { Message.count }.by(0)
        .and change { Event.count }.by(0)
    end

    it "appends to an existing open conversation when the contact messages again" do
      first  = PayloadFixtures.inbound_text
      second = PayloadFixtures.inbound_text(
        "message" => {"external_id" => "WAMID.DIFFERENT", "content" => "Segunda"}
      )

      described_class.call(channel, first)
      expect {
        described_class.call(channel, second)
      }.to change { Conversation.count }.by(0)
        .and change { Message.count }.by(1)
    end

    it "creates a new conversation when the previous one is resolved" do
      first  = PayloadFixtures.inbound_text
      described_class.call(channel, first)
      Conversation.last.update!(status: "resolved")

      second = PayloadFixtures.inbound_text(
        "message" => {"external_id" => "WAMID.NEWER", "content" => "Voltei"}
      )
      expect {
        described_class.call(channel, second)
      }.to change { Conversation.count }.by(1)
    end

    it "returns the persisted Message" do
      result = described_class.call(channel, PayloadFixtures.inbound_text)
      expect(result).to be_a(Message)
      expect(result).to be_persisted
    end
  end
end
```

- [ ] **Step 4: Run it — expect NameError**

```
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && unset DATABASE_URL && bundle exec rspec spec/services/ingestion/process_message_spec.rb"
```
Expected: `NameError: uninitialized constant Ingestion::ProcessMessage`.

- [ ] **Step 5: Implement the orchestrator**

Create `packages/app/app/services/ingestion/process_message.rb`:

```ruby
module Ingestion
  # Orchestrates the inbound message flow inside a single DB transaction.
  # Delegates to Contacts::Resolve, Conversations::ResolveOrCreate, and
  # Messages::Create. Short-circuits on duplicate external_id (no broadcast,
  # no second event). Flow advance + auto-assign are deferred to later specs.
  class ProcessMessage
    def self.call(channel, payload)
      ActiveRecord::Base.transaction do
        contact, contact_channel = Contacts::Resolve.call(channel, payload.fetch("contact"))
        conversation = Conversations::ResolveOrCreate.call(channel, contact, contact_channel)

        message_data = payload.fetch("message")
        message = Messages::Create.call(
          conversation: conversation,
          direction: "inbound",
          content: message_data["content"],
          content_type: message_data.fetch("content_type"),
          status: "received",
          sender: contact,
          external_id: message_data["external_id"],
          reply_to_external_id: message_data["reply_to_external_id"],
          sent_at: message_data["sent_at"],
          metadata: payload["metadata"].to_h,
          raw: payload["raw"]
        )

        return message if message.duplicate?

        broadcast(conversation, message)
        message
      end
    end

    def self.broadcast(conversation, message)
      Turbo::StreamsChannel.broadcast_append_to(
        "conversation:#{conversation.id}",
        target: "messages",
        partial: "dashboard/messages/message",
        locals: {message: message}
      )
    rescue => e
      # Broadcast failure must not roll back ingestion. Log only.
      Rails.logger.warn(
        event: "ingestion_broadcast_failed",
        conversation_id: conversation.id,
        message_id: message.id,
        error: e.message
      )
    end

    private_class_method :broadcast
  end
end
```

- [ ] **Step 6: Run the spec — expect all green**

```
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && unset DATABASE_URL && bundle exec rspec spec/services/ingestion/process_message_spec.rb"
```
Expected: 5 examples, 0 failures.

Note: the Turbo Stream broadcast will try to render `dashboard/messages/message` partial which doesn't exist yet in Plan 04a — the `rescue` clause swallows the error and logs. That's intentional: Plan 04b/later UI specs will create the partial; until then the broadcast is a no-op. The specs check DB state, not broadcast output.

- [ ] **Step 7: standardrb + commit**

```
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && bundle exec standardrb --fix"
git add packages/app/app/services/ingestion/process_message.rb packages/app/spec/services/ingestion/process_message_spec.rb packages/app/spec/support/payload_fixtures.rb packages/app/spec/rails_helper.rb
git commit -m "feat(app): add Ingestion::ProcessMessage orchestrator + payload fixtures"
```

---

## Task 6: `Ingestion::ProcessStatusUpdate` service

**Files:**
- Create: `packages/app/app/services/ingestion/process_status_update.rb`
- Create: `packages/app/spec/services/ingestion/process_status_update_spec.rb`

- [ ] **Step 1: Write the failing spec**

Create `packages/app/spec/services/ingestion/process_status_update_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Ingestion::ProcessStatusUpdate do
  let(:channel) do
    Channel.create!(channel_type: "whatsapp_cloud", identifier: "+5511999999999", name: "WhatsApp Sales")
  end
  let(:contact) { Contact.create!(name: "João") }
  let(:contact_channel) do
    ContactChannel.create!(channel: channel, contact: contact, source_id: "5511988888888")
  end
  let(:conversation) do
    channel.conversations.create!(
      contact: contact,
      contact_channel: contact_channel,
      status: "assigned",
      display_id: 1,
      last_activity_at: Time.current
    )
  end
  let!(:message) do
    Message.create!(
      channel: channel,
      conversation: conversation,
      direction: "outbound",
      content: "Olá",
      content_type: "text",
      status: "sent",
      external_id: "WAMID.ABC",
      sent_at: Time.current
    )
  end

  describe ".call" do
    it "updates the message status when the new status is later in the lifecycle" do
      payload = PayloadFixtures.status_update("external_id" => "WAMID.ABC", "status" => "delivered")
      result = described_class.call(channel, payload)

      expect(result).to eq(:updated)
      expect(message.reload.status).to eq("delivered")
    end

    it "emits messages:#{status} on a real update" do
      payload = PayloadFixtures.status_update("external_id" => "WAMID.ABC", "status" => "delivered")
      expect {
        described_class.call(channel, payload)
      }.to change { Event.where(name: "messages:delivered").count }.by(1)
    end

    it "is a no-op when the new status is not later (delivered does not overwrite read)" do
      message.update!(status: "read")
      payload = PayloadFixtures.status_update("external_id" => "WAMID.ABC", "status" => "delivered")

      expect(described_class.call(channel, payload)).to eq(:noop)
      expect(message.reload.status).to eq("read")
    end

    it "sets error and marks failed when status == failed at any point" do
      payload = PayloadFixtures.status_update(
        "external_id" => "WAMID.ABC",
        "status" => "failed",
        "error" => "Meta rate limit"
      )

      expect(described_class.call(channel, payload)).to eq(:updated)
      expect(message.reload.status).to eq("failed")
      expect(message.error).to eq("Meta rate limit")
    end

    it "is a no-op on SQS redelivery of the same status" do
      message.update!(status: "delivered")
      payload = PayloadFixtures.status_update("external_id" => "WAMID.ABC", "status" => "delivered")

      expect(described_class.call(channel, payload)).to eq(:noop)
      expect { described_class.call(channel, payload) }.to change { Event.count }.by(0)
    end

    it "returns :retry when no message with that external_id exists on this channel" do
      payload = PayloadFixtures.status_update("external_id" => "WAMID.UNKNOWN", "status" => "delivered")

      expect(described_class.call(channel, payload)).to eq(:retry)
    end
  end
end
```

- [ ] **Step 2: Run it — expect NameError**

```
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && unset DATABASE_URL && bundle exec rspec spec/services/ingestion/process_status_update_spec.rb"
```
Expected: `NameError: uninitialized constant Ingestion::ProcessStatusUpdate`.

- [ ] **Step 3: Implement the service**

Create `packages/app/app/services/ingestion/process_status_update.rb`:

```ruby
module Ingestion
  # Applies a provider status update (`sent → delivered → read`, or `failed`
  # at any point) to the matching outbound Message. Returns:
  #   :updated — status moved forward (or failed set)
  #   :noop    — already-current status or a backward-moving update
  #   :retry   — no message found; caller should return 422 so the
  #              channel container NACKs and SQS redelivers after the
  #              visibility timeout.
  class ProcessStatusUpdate
    LIFECYCLE = %w[pending sent delivered read].freeze

    def self.call(channel, payload)
      external_id = payload.fetch("external_id")
      message = channel.messages.find_by(external_id: external_id)
      return :retry unless message

      new_status = payload.fetch("status")
      return :noop unless progression_allowed?(message.status, new_status)

      attrs = {status: new_status}
      attrs[:error] = payload["error"] if payload["error"].present?
      message.update!(attrs)

      Events::Emit.call(name: "messages:#{new_status}", subject: message, actor: :system)

      broadcast(message)
      :updated
    end

    def self.progression_allowed?(current, incoming)
      return false if current == incoming
      return true  if incoming == "failed"
      LIFECYCLE.index(incoming).to_i > LIFECYCLE.index(current).to_i
    end

    def self.broadcast(message)
      Turbo::StreamsChannel.broadcast_replace_to(
        "conversation:#{message.conversation_id}",
        target: "message_#{message.id}_status",
        partial: "dashboard/messages/status",
        locals: {message: message}
      )
    rescue => e
      Rails.logger.warn(
        event: "status_update_broadcast_failed",
        message_id: message.id,
        error: e.message
      )
    end

    private_class_method :progression_allowed?, :broadcast
  end
end
```

- [ ] **Step 4: Run the spec — expect all green**

```
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && unset DATABASE_URL && bundle exec rspec spec/services/ingestion/process_status_update_spec.rb"
```
Expected: 6 examples, 0 failures.

- [ ] **Step 5: standardrb + commit**

```
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && bundle exec standardrb --fix"
git add packages/app/app/services/ingestion/process_status_update.rb packages/app/spec/services/ingestion/process_status_update_spec.rb
git commit -m "feat(app): add Ingestion::ProcessStatusUpdate with lifecycle-aware progression"
```

---

## Task 7: `Internal::IngestController`

**Files:**
- Create: `packages/app/app/controllers/internal/ingest_controller.rb`
- Create: `packages/app/spec/requests/internal/ingest_spec.rb`

- [ ] **Step 1: Write the failing request spec**

Create `packages/app/spec/requests/internal/ingest_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "POST /internal/ingest" do
  let!(:channel) do
    Channel.create!(channel_type: "whatsapp_cloud", identifier: "+5511999999999", name: "WhatsApp Sales")
  end

  def post_ingest(payload)
    post "/internal/ingest", params: payload.to_json, headers: {"Content-Type" => "application/json"}
  end

  context "valid inbound_message" do
    it "returns 200 and persists a Message" do
      expect {
        post_ingest(PayloadFixtures.inbound_text)
      }.to change { Message.count }.by(1)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("ok")
      expect(body["message_id"]).to be_a(Integer)
    end
  end

  context "duplicate external_id" do
    it "returns 200 and does NOT create a second Message" do
      payload = PayloadFixtures.inbound_text
      post_ingest(payload)
      expect {
        post_ingest(payload)
      }.to change { Message.count }.by(0)
      expect(response).to have_http_status(:ok)
    end
  end

  context "unregistered channel identifier" do
    it "returns 422 and writes nothing" do
      payload = PayloadFixtures.inbound_text(
        "channel" => {"type" => "whatsapp_cloud", "identifier" => "+5500000000000"}
      )
      expect {
        post_ingest(payload)
      }.to change { Message.count }.by(0)
       .and change { Contact.count }.by(0)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  context "inactive channel" do
    before { channel.update!(active: false) }

    it "returns 422" do
      post_ingest(PayloadFixtures.inbound_text)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  context "schema-invalid payload (missing required field)" do
    it "returns 422" do
      payload = PayloadFixtures.inbound_text
      payload["message"].delete("external_id")
      post_ingest(payload)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  context "valid outbound_status_update" do
    let!(:message) do
      contact = Contact.create!(name: "João")
      contact_channel = ContactChannel.create!(channel: channel, contact: contact, source_id: "5511988888888")
      conversation = channel.conversations.create!(
        contact: contact, contact_channel: contact_channel,
        status: "assigned", display_id: 1, last_activity_at: Time.current
      )
      Message.create!(
        channel: channel, conversation: conversation, direction: "outbound",
        content: "Olá", content_type: "text", status: "sent",
        external_id: "WAMID.XYZ", sent_at: Time.current
      )
    end

    it "updates status and returns 200" do
      post_ingest(PayloadFixtures.status_update("external_id" => "WAMID.XYZ", "status" => "delivered"))
      expect(response).to have_http_status(:ok)
      expect(message.reload.status).to eq("delivered")
    end
  end

  context "status update for unknown external_id" do
    it "returns 422 so the container NACKs" do
      post_ingest(PayloadFixtures.status_update("external_id" => "WAMID.UNKNOWN", "status" => "delivered"))
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
```

- [ ] **Step 2: Run it — expect UnknownController / RoutingError**

```
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && unset DATABASE_URL && bundle exec rspec spec/requests/internal/ingest_spec.rb"
```
Expected: uninitialized constant `Internal::IngestController` (or 404 on the first request).

- [ ] **Step 3: Implement the controller**

Create `packages/app/app/controllers/internal/ingest_controller.rb`:

```ruby
module Internal
  # Unauthenticated at the app layer — security is the ingress boundary.
  # See ARCHITECTURE.md § Security → /internal/ingest authentication.
  # Still enforced: Channel registration lookup + schema validation.
  class IngestController < ApplicationController
    allow_unauthenticated_access only: :create
    skip_forgery_protection only: :create

    def create
      payload = request.request_parameters
      payload = JSON.parse(request.raw_post) if payload.blank? && request.raw_post.present?

      FaleComChannel::Payload.validate!(payload.transform_keys(&:to_s))

      channel = Channel.find_by(
        channel_type: payload.dig("channel", "type"),
        identifier: payload.dig("channel", "identifier")
      )
      return render_422("unknown_channel") unless channel&.active?

      case payload["type"]
      when "inbound_message"
        message = Ingestion::ProcessMessage.call(channel, payload)
        render json: {status: "ok", message_id: message.id}
      when "outbound_status_update"
        result = Ingestion::ProcessStatusUpdate.call(channel, payload)
        case result
        when :retry then render_422("unknown_external_id")
        else render json: {status: "ok"}
        end
      else
        render_422("unknown_type")
      end
    rescue FaleComChannel::ValidationError, JSON::ParserError => e
      render_422(e.message)
    end

    private

    def render_422(reason)
      render json: {status: "error", reason: reason}, status: :unprocessable_entity
    end
  end
end
```

- [ ] **Step 4: Run the spec — expect all green**

```
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && unset DATABASE_URL && bundle exec rspec spec/requests/internal/ingest_spec.rb"
```
Expected: 7 examples, 0 failures.

If the spec fails with `NameError: FaleComChannel::ValidationError` or `Payload.validate!`, check `packages/falecom_channel/lib/falecom_channel/payload.rb` for the exact exception class (Plan 03 shipped it — open the file and swap the rescue class if needed). Do **not** change the gem — change the rescue to match what Plan 03 actually raised.

- [ ] **Step 5: standardrb + commit**

```
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && bundle exec standardrb --fix"
git add packages/app/app/controllers/internal/ingest_controller.rb packages/app/spec/requests/internal/ingest_spec.rb
git commit -m "feat(app): add Internal::IngestController — schema + channel lookup + route by type"
```

---

## Task 8: `rake ingest:mock` dev utility

**Files:**
- Create: `packages/app/lib/tasks/ingest.rake`
- Create: `packages/app/spec/tasks/ingest_spec.rb`

- [ ] **Step 1: Write the failing spec**

Create `packages/app/spec/tasks/ingest_spec.rb`:

```ruby
require "rails_helper"
require "rake"

RSpec.describe "ingest:mock rake task" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("ingest:mock")
  end

  before do
    Rake::Task["ingest:mock"].reenable
    Channel.create!(channel_type: "whatsapp_cloud", identifier: "+5511999999999", name: "WhatsApp Sales")
  end

  it "creates a Message via Ingestion::ProcessMessage when run with default args" do
    expect {
      silence_stream($stdout) { Rake::Task["ingest:mock"].invoke }
    }.to change { Message.count }.by(1)
  end

  it "passes the provided content through to the Message" do
    silence_stream($stdout) { Rake::Task["ingest:mock"].invoke("hello from rake") }
    expect(Message.last.content).to eq("hello from rake")
  end

  # Rails 8 doesn't ship the old `silence_stream` helper; polyfill inline.
  def silence_stream(stream)
    old = stream.dup
    stream.reopen(IO::NULL)
    yield
  ensure
    stream.reopen(old)
  end
end
```

- [ ] **Step 2: Run it — expect failure**

```
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && unset DATABASE_URL && bundle exec rspec spec/tasks/ingest_spec.rb"
```
Expected: `Don't know how to build task 'ingest:mock'`.

- [ ] **Step 3: Implement the rake task**

Create `packages/app/lib/tasks/ingest.rake`:

```ruby
namespace :ingest do
  desc "Drive Ingestion::ProcessMessage with a mock inbound text payload. Usage: bin/rails 'ingest:mock[Hello from dev]'"
  task :mock, [:content] => :environment do |_t, args|
    channel = Channel.first || abort("No Channel found. Run bin/rails db:seed first.")
    content = args[:content].presence || "Mock message at #{Time.current.iso8601}"

    payload = {
      "type" => "inbound_message",
      "channel" => {"type" => channel.channel_type, "identifier" => channel.identifier},
      "contact" => {
        "source_id" => "mock_#{SecureRandom.hex(4)}",
        "name" => "Mock User"
      },
      "message" => {
        "external_id" => "MOCK_#{SecureRandom.hex(6)}",
        "direction" => "inbound",
        "content" => content,
        "content_type" => "text",
        "attachments" => [],
        "sent_at" => Time.current.iso8601
      },
      "metadata" => {},
      "raw" => {}
    }

    message = Ingestion::ProcessMessage.call(channel, payload)
    puts "Ingested Message##{message.id} on Conversation##{message.conversation_id}: #{content}"
  end
end
```

- [ ] **Step 4: Run the spec — expect all green**

```
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && unset DATABASE_URL && bundle exec rspec spec/tasks/ingest_spec.rb"
```
Expected: 2 examples, 0 failures.

- [ ] **Step 5: standardrb + commit**

```
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && bundle exec standardrb --fix"
git add packages/app/lib/tasks/ingest.rake packages/app/spec/tasks/ingest_spec.rb
git commit -m "feat(app): add rake ingest:mock dev utility driving Ingestion::ProcessMessage"
```

---

## Task 9: Regression sweep — full app + gem suites

- [ ] **Step 1: Run full `packages/app` suite**

```
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && unset DATABASE_URL && bundle exec rspec"
```
Expected: all examples pass — pre-existing Spec 02 specs (99 examples) plus the new Plan 04a specs (~35 new examples = 7 + 9 + 6 + 5 + 6 + 7 + 2). Total ~134.

- [ ] **Step 2: Run full gem suite**

```
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/falecom_channel && bundle exec rspec"
```
Expected: 117 examples, 0 failures (unchanged — gem not modified in this plan).

- [ ] **Step 3: standardrb across both packages**

```
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && bundle exec standardrb"
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/falecom_channel && bundle exec standardrb"
```
Expected: both clean.

- [ ] **Step 4: Manual smoke via rake**

```
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && bin/rails 'ingest:mock[smoke test from plan 04a]'"
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && bin/rails runner 'puts Message.last.inspect'"
```
Expected: rake prints `Ingested Message#…`; runner shows the persisted record with `content_type: \"text\"` and `direction: \"inbound\"`.

- [ ] **Step 5: Update `docs/PROGRESS.md`**

Edit the Plans table: add a row for `04a`. Example:

```
| 04a | [Phase 4A — Ingestion Rails](./plans/04a-2026-04-22-ingestion-pipeline-rails.md) | 04   | In Progress | —   | —          |
```

Flip Spec 04 from `Draft` → `In Progress` in the Specs table.

- [ ] **Step 6: Commit + push**

```
git add docs/PROGRESS.md
git commit -m "docs(progress): mark Plan 04a In Progress"
```

Plan 04a ends here. Opening a PR (or merging to main per session convention) happens after this commit.

---

## What this plan does NOT do

These items are **explicitly deferred to Plan 04b** (container + infra):

- `packages/channels/whatsapp-cloud/` — Parser, SignatureVerifier, Sender, Consumer entry point.
- `infra/dev-webhook/` — Roda app that mimics API Gateway locally.
- `infra/docker-compose.yml` — LocalStack service, `app`, `app-jobs`, `channel-whatsapp-cloud`, `dev-webhook` services uncommented.
- End-to-end pipeline test at `packages/channels/whatsapp-cloud/spec/e2e/pipeline_spec.rb` driving a real SQS round-trip.
- Turbo Stream partials (`dashboard/messages/_message.html.erb`, `dashboard/messages/_status.html.erb`) — Plan 04a's broadcasts are resilient to missing partials (`rescue => e` in the services).
