# Spec: Ingestion Pipeline (Rails + WhatsApp Cloud Container)

> **Phase:** 3 (Ingestion pipeline) — Rails endpoint + first container
> **Execution Order:** 4 of 7 — after Specs 2 and 3 are both complete
> **Date:** 2026-04-17
> **Status:** Draft — awaiting approval
> **Depends on:**
> - [Spec 2: Core Domain Models](./02-core-domain-models.md) (database schema exists)
> - [Spec 3: falecom_channel Gem](./03-falecom-channel-gem.md) (payload schema, queue adapter, consumer, ingest client exist)

---

## 1. What problem are we solving?

The domain models exist (Spec 2) and the shared gem defines the contract (Spec 3), but there is no way for a message to enter the system. We need:

1. A Rails endpoint (`/internal/ingest`) that accepts the Common Ingestion Payload, validates it, and processes it into domain records.
2. A reference channel container (WhatsApp Cloud) that translates Meta's webhook format into the common payload and POSTs it to Rails.

After this spec, a message pulled from an SQS queue → WhatsApp container → Rails → database → Turbo Stream broadcast is a working path.

---

## 2. What is in scope?

### 2.1 Rails — `Internal::IngestController`

```
POST /internal/ingest
```

**Authentication:**
- HMAC verification via `FaleComChannel::Hmac.verify!` (or a Ruby-side reimplementation).
- Checks `X-FaleCom-Signature` header.
- Rejects with `401 Unauthorized` if signature is invalid. Note: We don't strictly validate timestamps/replay since we are pulling securely from SQS queues.

**Channel registration check:**
```ruby
channel = Channel.find_by(
  channel_type: payload.dig("channel", "type"),
  identifier: payload.dig("channel", "identifier")
)
return head :unprocessable_entity unless channel&.active?
```

**Routing by `type`:**

| `type` | Handler |
|---|---|
| `inbound_message` | `Ingestion::ProcessMessage.call(channel, payload)` |
| `outbound_status_update` | `Ingestion::ProcessStatusUpdate.call(channel, payload)` |

**Response:** `200 OK` with `{ "status": "ok" }` on success. `422` on validation failure. `401` on auth failure.

### 2.2 `Ingestion::ProcessMessage` Service

Runs inside a single database transaction. This is the core inbound path.

```
Ingestion::ProcessMessage.call(channel, payload)
  1. Contacts::Resolve.call(channel, payload["contact"])
     → find or create Contact + ContactChannel by (channel_id, source_id)
     → merge name/phone/email/avatar from payload into Contact if provided

  2. Conversations::ResolveOrCreate.call(channel, contact_channel)
     → find open conversation (status != resolved) for this contact_channel
     → if none exists: create new conversation
       - status: "bot" if channel has an active flow, else "queued"
       - display_id: next per-account sequence
       - last_activity_at: now
     → emit conversations:created event if new

  3. Messages::Create.call(conversation, payload["message"], payload["metadata"], payload["raw"])
     → create Message record with:
       - direction: inbound
       - sender: contact
       - content, content_type, external_id, sent_at, metadata, raw
       - status: "received"
     → idempotency: ON CONFLICT (channel_id, external_id) DO NOTHING
       - if duplicate, return existing message, skip remaining steps
     → update conversation.last_activity_at
     → emit messages:inbound event

  4. Handle attachments:
     → if payload["message"]["attachments"] is non-empty:
       - enqueue DownloadAttachmentJob for each attachment
       - store attachment metadata on the message record

  5. Broadcast:
     → Turbo::StreamsChannel.broadcast_* to conversation and workspace channels
     → (Flow advance is NOT in scope here — deferred to Flow Engine spec)
```

### 2.3 `Ingestion::ProcessStatusUpdate` Service

Updates message delivery status.

```
Ingestion::ProcessStatusUpdate.call(channel, payload)
  1. Find message by (channel_id, external_id)
     → if not found, log warning and return (provider may send statuses for messages we didn't send)

  2. Update message.status to payload["status"]
     → only if the new status is "later" in the lifecycle (sent → delivered → read)
     → failed can arrive at any point

  3. If payload["error"], set message.error

  4. Emit messages:#{status} event (messages:delivered, messages:read, messages:failed)

  5. Broadcast updated message status via Turbo Stream
```

### 2.4 `Contacts::Resolve` Service

```ruby
class Contacts::Resolve
  def self.call(channel, contact_data)
    contact_channel = ContactChannel.find_or_initialize_by(
      channel: channel,
      source_id: contact_data["source_id"]
    )

    if contact_channel.new_record?
      contact = channel.account.contacts.create!(
        name: contact_data["name"],
        phone_number: contact_data["phone_number"],
        email: contact_data["email"]
      )
      contact_channel.contact = contact
      contact_channel.save!
      Events::Emit.call(name: "contacts:created", subject: contact, actor: :system)
      Events::Emit.call(name: "contact_channels:created", subject: contact_channel, actor: :system)
    else
      contact = contact_channel.contact
      # Merge provided fields (don't overwrite with nil)
      contact.update!(
        contact_data.slice("name", "phone_number", "email", "avatar_url")
          .compact.transform_keys(&:to_sym)
          .reject { |k, v| contact.send(k).present? && v.blank? }
      )
    end

    [contact, contact_channel]
  end
end
```

### 2.5 `Conversations::ResolveOrCreate` Service

```ruby
class Conversations::ResolveOrCreate
  def self.call(channel, contact, contact_channel)
    conversation = channel.conversations
      .where(contact_channel: contact_channel)
      .where.not(status: "resolved")
      .order(created_at: :desc)
      .first

    if conversation
      conversation
    else
      conversation = channel.conversations.create!(
        account: channel.account,
        contact: contact,
        contact_channel: contact_channel,
        status: channel.active_flow_id? ? "bot" : "queued",
        display_id: next_display_id(channel.account),
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
end
```

### 2.6 `DownloadAttachmentJob`

```ruby
class DownloadAttachmentJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  def perform(message_id, attachment_data)
    message = Message.find(message_id)
    # Download from attachment_data["external_url"]
    # Attach via Active Storage
    # message.files.attach(io: downloaded_file, filename: attachment_data["filename"], content_type: attachment_data["content_type"])
  end
end
```

### 2.7 `packages/channels/whatsapp-cloud/` — Reference Container

The first channel container. Uses the `falecom_channel` gem.

**Files:**

| File | Purpose |
|---|---|
| `app.rb` | Main app — includes Consumer, starts polling |
| `config.ru` | Rackup for the SendServer |
| `lib/parser.rb` | Meta webhook → Common Ingestion Payload |
| `lib/signature_verifier.rb` | Validates `X-Hub-Signature-256` |
| `lib/sender.rb` | Common outbound → Meta Cloud API call |
| `Gemfile` | `gem "falecom_channel", path: "../../falecom_channel"` |
| `Dockerfile` | Container image |
| `spec/` | RSpec tests |

**`Parser`:**
- Takes Meta's webhook payload (`entry[0].changes[0].value.messages[0]` nesting).
- Handles message types: text, image, audio, video, document, location, contacts, interactive (button/list replies).
- Handles status updates (`entry[0].changes[0].value.statuses[0]`).
- Maps to Common Ingestion Payload.
- Puts Meta-specific fields in `metadata.whatsapp_context`.

**`SignatureVerifier`:**
- Verifies `X-Hub-Signature-256` header against the raw body using the app secret.
- Raises `FaleComChannel::SignatureError` on failure.

**`Sender`:**
- POSTs to Meta Cloud API (`graph.facebook.com/v21.0/{phone_number_id}/messages`).
- Maps common outbound payload → Meta message format.
- Returns `{ external_id: response["messages"][0]["id"] }`.
- Uses channel credentials from the `/send` payload metadata or ENV.

**Target size:** ~200–300 lines total across all files plus tests.

### 2.8 Docker Compose Updates

Uncomment the `channel-whatsapp-cloud` and `app` services in `infra/docker-compose.yml`. Wire environment variables, ensuring it points to an SQS queue (via real AWS or LocalStack).

### 2.10 Tests

- [ ] **`Internal::IngestController` request specs:**
  - Valid inbound message → 200, message created, conversation created, event emitted.
  - Valid status update → 200, message status updated.
  - Invalid HMAC → 401.
  - Unknown channel → 422.
  - Duplicate `external_id` → 200 (idempotent, no duplicate message).

- [ ] **`Ingestion::ProcessMessage` service specs:**
  - New contact + new conversation → creates both, emits events.
  - Existing contact + existing conversation → appends message to existing.
  - Resolved conversation + new message → creates new conversation.
  - Idempotent on duplicate `external_id`.

- [ ] **`Contacts::Resolve` specs:**
  - New source_id → creates Contact + ContactChannel.
  - Existing source_id → returns existing, merges new fields without overwriting.

- [ ] **`Conversations::ResolveOrCreate` specs:**
  - Open conversation exists → returns it.
  - Only resolved conversations exist → creates new.
  - No conversations → creates new with correct status (`bot` or `queued`).

- [ ] **WhatsApp Cloud parser specs:**
  - Text message → correct common payload.
  - Image with caption → correct payload with attachment.
  - Status update → correct status update payload.
  - Invalid signature → raises.

- [ ] **End-to-end integration test:**
  - Mock SQS payload with a real Meta-format webhook.
  - `whatsapp-cloud` container pulls from the queue, parses, POSTs to `/internal/ingest`.
  - Verify: Message record exists in DB, Conversation created, Contact created, Events emitted.

---

## 3. What is out of scope?

- **Outbound dispatch** (agent reply → SendMessageJob → container `/send`) — Spec 5.
- **Flow engine** (advancing bot flow on inbound message) — Spec 7. The `Ingestion::ProcessMessage` service creates the conversation with `status: "bot"` if a flow is configured, but does NOT call `Flows::Advance`.
- **Auto-assignment** — Spec 6. The service sets status to `queued` but does not call `Assignments::AutoAssign`.
- **Other channel containers** (Z-API, Evolution, Instagram, Telegram) — separate specs.
- **Terraform configuration** — infrastructure spec.
- **Dashboard views** — conversations and messages appear in the database but are not rendered in the UI yet.

---

## 4. What changes about the system?

After this spec:

- Messages can enter the system end-to-end: SQS → container → Rails → database.
- The `/internal/ingest` endpoint is live and HMAC-protected.
- Contact resolution, conversation management, and message creation are working services.
- Idempotency ensures SQS redelivery never creates duplicates.
- The WhatsApp Cloud container is the reference implementation for all future channel containers.
- Turbo Stream broadcasts fire on message creation — the dashboard (when UI is built) will update in real-time.

This implements `ARCHITECTURE.md § Inbound Message Flow` (steps 1–10, minus flow advance and auto-assign) and `ARCHITECTURE.md § Build Order → Phase 3`.

---

## 5. Acceptance criteria

1. `POST /internal/ingest` with a valid HMAC-signed inbound message payload returns 200 and creates a Message record.
2. The same POST with an invalid HMAC returns 401.
3. The same POST with an unregistered `channel_type + identifier` returns 422.
4. Sending the same `external_id` twice creates only one Message (idempotency).
5. A new contact arriving on a channel creates a Contact + ContactChannel.
6. A message on a channel with no open conversation creates a new Conversation.
7. `Events` table has entries for `contacts:created`, `conversations:created`, and `messages:inbound`.
8. WhatsApp Cloud parser correctly transforms a real Meta text message webhook into Common Ingestion Payload.
9. End-to-end test: SQS pull → container processes → message appears in Rails DB.
10. `bundle exec rspec` in `packages/app`, `packages/channels/whatsapp-cloud`, and `packages/falecom_channel` all pass.
11. `bundle exec standardrb` passes across all packages.

---

## 6. Risks

- **Meta webhook format changes** — Meta occasionally modifies their webhook payload structure. Mitigation: the parser is isolated in one file; tests pin the expected format; the `raw` field preserves the original for debugging.
- **Transaction scope of ProcessMessage** — wrapping contact resolve + conversation resolve + message create in one transaction is clean but could be slow under load. Mitigation: the transaction only hits Postgres (no external calls inside it); attachments are downloaded asynchronously.

---

## 7. Open questions

1. **Conversation reopening** — When a contact sends a message to a channel with a resolved conversation, should we always create a new conversation, or should there be a "reopen window" (e.g., within 24 hours)? The architecture says "configurable" — this decision can be deferred to a follow-up spec. For now, always create new.
2. **WhatsApp Cloud API version** — Meta deprecates API versions on a rolling basis. Should the container pin a specific API version (`v21.0`) or use `v{latest}`? Recommendation: pin the version, add it as a constant, and update it explicitly.
