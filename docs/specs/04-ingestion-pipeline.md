# Spec: Ingestion Pipeline (Rails + WhatsApp Cloud Container)

> **Phase:** 3 (Ingestion pipeline) — Rails endpoint + first channel container
> **Execution Order:** 4 of 7 — after Specs 2 and 3 are both complete
> **Date:** 2026-04-17 (v1), 2026-04-21 (v2 hardening pass)
> **Status:** Draft — awaiting approval
> **Depends on:**
> - [Spec 2: Core Domain Models](./02-core-domain-models.md) (database schema exists)
> - [Spec 3: falecom_channel Gem](./03-falecom-channel-gem.md) (payload schema, queue adapter, consumer, ingest client exist)

---

## v2 hardening changes (2026-04-21)

This pass resolves contradictions surfaced during the brainstorming review:

1. **Ingest HMAC dropped.** `/internal/ingest` is unauthenticated at the application layer. Security is the ingress boundary (operator must not expose `/internal/*` publicly) plus the Channel registration lookup + `(channel_id, external_id)` idempotency index. ARCHITECTURE.md `§ Security → /internal/ingest authentication` rewritten in the same PR. `FaleComChannel::IngestClient` no longer signs requests. `FALECOM_INGEST_HMAC_SECRET` env var deleted everywhere. Dispatch (`Rails → container /send`) keeps HMAC — asymmetric by design.
2. **Service signatures unified.** `Conversations::ResolveOrCreate.call(channel, contact, contact_channel)` — three args, matches its own code block.
3. **Cross-instance contact dedup deferred.** Added to `§ Out of scope` explicitly. Only exact-match (channel_id, source_id) + universal-match (phone_number, email) ship in Plan 04.
4. **`with_advisory_lock` gem dropped.** Use inline `pg_advisory_xact_lock(hashtext('display_id'))` inside the `Ingestion::ProcessMessage` transaction — transaction-scoped, auto-released, no gem dependency.
5. **`whatsapp_sdk` gem dropped.** Parser + sender hand-rolled with Faraday. Matches the style of `IngestClient` and `DispatchClient`, avoids a dependency, ~50 lines total.
6. **Scope cut to text-only.** Parser, sender, and status-update handling cover `content_type: "text"` only. Media (image/audio/video/document), location, contacts, and interactive replies (button/list) deferred to a follow-up plan. Attachments array is always `[]` in v1 output.
7. **`DownloadAttachmentJob` deferred.** Out of scope with the text-only cut.
8. **`ProcessStatusUpdate` retry wording fixed.** Controller is synchronous. Missing-message returns `422`; the channel container NACKs the SQS message; SQS redelivers after visibility timeout. Not "Solid Queue retry".
9. **`Contacts::Resolve` rewritten.** The broken `unless ... == false` guard is replaced with `contact.previously_new_record?` checked after the assignment that actually created it.
10. **End-to-end test home fixed.** Lives at `packages/channels/whatsapp-cloud/spec/e2e/pipeline_spec.rb`, drives the real WhatsApp container against LocalStack SQS + a live Rails app started in-process via `Rack::Server`.
11. **Compose additions named.** LocalStack service added. Placeholders for `app`, `app-jobs`, `channel-whatsapp-cloud`, and `dev-webhook` uncommented with the env vars confirmed in this spec.
12. **Admin UI for Channel CRUD not in scope.** Seed data covers dev. Move to Spec 06 (workspace UI) or later.

---

## 1. What problem are we solving?

The domain models exist (Spec 2) and the shared gem defines the contract (Spec 3), but there is no way for a message to enter the system. We need:

1. A Rails endpoint (`/internal/ingest`) that accepts the Common Ingestion Payload, looks up the registered channel, and processes it into domain records.
2. A reference channel container (WhatsApp Cloud) that translates Meta's webhook format into the common payload and POSTs it to Rails.

After this spec, a message pulled from an SQS queue → WhatsApp container → Rails → database → Turbo Stream broadcast is a working path, end-to-end, with a live integration test proving it.

---

## 2. What is in scope?

### 2.1 Rails — `Internal::IngestController`

```
POST /internal/ingest
```

**Security:** the route is unauthenticated at the app layer. The two checks the controller performs are:

1. **Channel registration lookup.** Rejects unknown or inactive channels with 422.

   ```ruby
   channel = Channel.find_by(
     channel_type: payload.dig("channel", "type"),
     identifier:   payload.dig("channel", "identifier")
   )
   return head :unprocessable_entity unless channel&.active?
   ```

2. **Payload schema validation.** `FaleComChannel::Payload.validate!` gates the request before any DB write. 422 on schema error.

Ingress configuration — keeping `/internal/*` off public listeners — is the real security boundary. This is documented in `ARCHITECTURE.md § Security` and is the operator's responsibility.

**Routing by `type`:**

| `type` | Handler |
|---|---|
| `inbound_message` | `Ingestion::ProcessMessage.call(channel, payload)` |
| `outbound_status_update` | `Ingestion::ProcessStatusUpdate.call(channel, payload)` |

**Response:** `200 OK` with `{ "status": "ok", "message_id": <id_if_created_or_existing> }` on success. `422` on validation failure or unknown channel. `500` bubbles up untouched (Rack default) for any unexpected error — the container NACKs and SQS redelivers.

### 2.2 `Ingestion::ProcessMessage` Service

Runs inside a single database transaction.

```ruby
contact, contact_channel = Contacts::Resolve.call(channel, payload["contact"])
conversation             = Conversations::ResolveOrCreate.call(channel, contact, contact_channel)

message_data = payload["message"]
message = Messages::Create.call(
  conversation:         conversation,
  direction:            "inbound",
  content:              message_data["content"],
  content_type:         message_data.fetch("content_type"),
  status:               "received",
  sender:               contact,
  external_id:          message_data["external_id"],
  reply_to_external_id: message_data["reply_to_external_id"],
  sent_at:              message_data["sent_at"],
  metadata:             payload["metadata"].to_h,
  raw:                  payload["raw"]
)

# Idempotent via ON CONFLICT (channel_id, external_id) DO NOTHING — if the row
# already exists, Messages::Create returns the existing record with a sentinel
# flag and the service short-circuits: no broadcast, no duplicate event.
return message if message.duplicate?

# Broadcast — Flow advance is deferred to Spec 07 (Flow Engine).
Turbo::StreamsChannel.broadcast_append_to(
  "conversation:#{conversation.id}",
  target: "messages",
  partial: "dashboard/messages/message",
  locals:  { message: message }
)

message
```

Attachments are out of scope in v2 — `payload["message"]["attachments"]` is always `[]` for text-only messages from the WhatsApp container. Spec stores whatever the payload sent as metadata but does not enqueue a download job. The `DownloadAttachmentJob` lives in a follow-up spec together with the non-text content types.

### 2.3 `Ingestion::ProcessStatusUpdate` Service

```
Ingestion::ProcessStatusUpdate.call(channel, payload)
  1. message = channel.messages.find_by(external_id: payload["external_id"])
     → if not found: return { retry: true } — the controller renders 422 with this
       hint in the body. The channel container NACKs, SQS redelivers after the
       visibility timeout, and the next delivery tries again. This is a queue-level
       retry (SQS), not a Solid Queue retry — Solid Queue is not involved in ingest.

  2. Idempotency guard:
     → if message.status == payload["status"], return (no-op on SQS redelivery).

  3. Update message.status — but only if the new value is "later" in the lifecycle:
        sent → delivered → read
     failed may arrive at any point and always wins.

  4. If payload["error"] present, set message.error.

  5. Emit "messages:#{status}" event (messages:sent | delivered | read | failed).

  6. Broadcast updated message via Turbo Stream.
```

### 2.4 `Contacts::Resolve` Service

```ruby
class Contacts::Resolve
  def self.call(channel, contact_data)
    contact_channel = ContactChannel.find_or_initialize_by(
      channel: channel,
      source_id: contact_data.fetch("source_id")
    )

    if contact_channel.new_record?
      contact =
        find_existing_contact(contact_data) ||
        Contact.create!(
          name:         contact_data["name"],
          phone_number: contact_data["phone_number"],
          email:        contact_data["email"]
        )

      contact_channel.contact = contact
      contact_channel.save!

      Events::Emit.call(name: "contacts:created", subject: contact, actor: :system) if contact.previously_new_record?
      Events::Emit.call(name: "contact_channels:created", subject: contact_channel, actor: :system)
    else
      contact = contact_channel.contact
      merge_contact_fields!(contact, contact_data)
    end

    [contact, contact_channel]
  end

  # Universal dedup: same person reappearing via phone or email. Scoped
  # to this account (single-tenant — every contact already belongs to
  # the single account, so no explicit account scope is needed).
  def self.find_existing_contact(contact_data)
    return Contact.find_by(phone_number: contact_data["phone_number"]) if contact_data["phone_number"].present?
    return Contact.find_by(email: contact_data["email"]) if contact_data["email"].present?
    nil
  end

  # Provider-reported data (from every inbound payload) does NOT overwrite
  # existing non-blank fields. Two exceptions will come later:
  # - Bot-collected data in Spec 07 `Flows::Handoff` is explicit user intent
  #   and overrides via a direct `contact.update!(name: …)` — not this helper.
  # - Manual agent edits in Spec 06 (`Dashboard::ContactsController#update`)
  #   override via their own code path.
  # This helper is the auto-merge path; it is conservative by design.
  def self.merge_contact_fields!(contact, contact_data)
    updates = {}
    %w[name phone_number email avatar_url].each do |field|
      incoming = contact_data[field]
      next if incoming.blank?
      next if contact.public_send(field).present? && contact.public_send(field) != incoming
      updates[field] = incoming
    end
    contact.update!(updates) if updates.any?
  end
end
```

**Deferred: cross-instance identification.** `ARCHITECTURE.md § Inbound Message Flow` step 9.2 ("Cross-Instance Match: searches same source_id in other channels of the same type") is intentionally NOT implemented in Plan 04. It only matters once operators deploy multiple WhatsApp numbers for the same business. Tracked as a follow-up.

### 2.5 `Conversations::ResolveOrCreate` Service

```ruby
class Conversations::ResolveOrCreate
  def self.call(channel, contact, contact_channel)
    # Serialize display_id generation across concurrent ingestion workers.
    # Transaction-scoped lock auto-releases on commit/rollback — no gem dep,
    # no explicit unlock.
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
        contact:           contact,
        contact_channel:   contact_channel,
        status:            channel.active_flow_id? ? "bot" : "queued",
        display_id:        (Conversation.maximum(:display_id) || 0) + 1,
        last_activity_at:  Time.current
      )

      Events::Emit.call(
        name:    "conversations:created",
        subject: conversation,
        actor:   :system
      )

      conversation
    end
  end
end
```

The partial unique index `index_conversations_open_per_contact_channel` (from Spec 02) provides the last-line-of-defense against two open conversations per contact_channel — if the advisory lock fails for any reason, the insert itself will violate the unique constraint, which is caught and retried at the service call site (rare edge case; tested).

### 2.6 `Messages::Create` Service

Single kwargs-based entry point for **all** message creation across the app:
- inbound (from `Ingestion::ProcessMessage`, this spec)
- outbound from agents (Spec 05 `Dispatch::Outbound`)
- outbound from bot (Spec 07 `Flows::Advance`)
- system messages with no provider delivery (Spec 06 transfer notes)

```ruby
class Messages::Create
  # Returns a Message. On duplicate (channel_id, external_id), returns the existing
  # record marked with #duplicate? so callers can short-circuit without a second
  # broadcast or event emission.
  def self.call(conversation:, direction:, content:, content_type:, status:, sender: nil,
                external_id: nil, reply_to_external_id: nil, sent_at: nil,
                metadata: {}, raw: nil)
    attrs = {
      channel_id:           conversation.channel_id,
      conversation_id:      conversation.id,
      direction:            direction,
      content:              content,
      content_type:         content_type,
      status:               status,
      sender_type:          sender&.class&.base_class&.name,
      sender_id:            sender&.id,
      external_id:          external_id,
      reply_to_external_id: reply_to_external_id,
      sent_at:              sent_at,
      metadata:             metadata.to_h,
      raw:                  raw
    }

    # ON CONFLICT via the partial unique index (channel_id, external_id)
    # WHERE external_id IS NOT NULL. System messages (no external_id) always
    # insert; provider-correlated messages dedup.
    if external_id.present?
      result = Message.insert_all(
        [attrs.merge(created_at: Time.current, updated_at: Time.current)],
        returning: [:id],
        unique_by: :index_messages_on_channel_id_and_external_id
      )

      if result.rows.empty?
        existing = Message.find_by!(
          channel_id:  conversation.channel_id,
          external_id: external_id
        )
        existing.define_singleton_method(:duplicate?) { true }
        return existing
      end

      message = Message.find(result.rows.first.first)
    else
      message = Message.create!(attrs)
    end

    message.define_singleton_method(:duplicate?) { false }
    conversation.update!(last_activity_at: Time.current)

    event_name = direction == "inbound" ? "messages:inbound" : "messages:outbound"
    Events::Emit.call(name: event_name, subject: message, actor: sender || :system)

    message
  end
end
```

**Callers pass the shape they need:**

| Caller | Typical kwargs |
|---|---|
| `Ingestion::ProcessMessage` (this spec) | `direction: "inbound"`, `status: "received"`, `sender: contact`, `external_id:`, `sent_at:`, `metadata:`, `raw:` |
| `Dispatch::Outbound` (Spec 05) | `direction: "outbound"`, `status: "pending"`, `sender: user_or_bot`, `reply_to_external_id:` |
| `Flows::Advance` / `Flows::Handoff` (Spec 07) | `direction: "outbound"`, `status: "pending"`, `sender: :bot` (or a Bot singleton model) |
| `Assignments::Transfer` system note (Spec 06) | `direction: "outbound"`, `status: "received"` (never leaves Rails), `sender: :system`, no `external_id` |

### 2.7 `packages/channels/whatsapp-cloud/` — Reference Container

The first channel container. Uses the `falecom_channel` gem.

**Files:**

| File | Purpose |
|---|---|
| `app.rb` | Main entry — includes `FaleComChannel::Consumer`, implements `#handle` |
| `config.ru` | Rackup for the `/send` server |
| `lib/parser.rb` | Meta webhook JSON → Common Ingestion Payload (text only) |
| `lib/signature_verifier.rb` | Validates `X-Hub-Signature-256` from Meta |
| `lib/sender.rb` | Common outbound → Meta Cloud API call (text only) |
| `Gemfile` | `gem "falecom_channel", path: "../../falecom_channel"` + `faraday` |
| `Dockerfile` | Container image |
| `spec/parser_spec.rb` | Text inbound + text status update |
| `spec/signature_verifier_spec.rb` | Valid + invalid signatures |
| `spec/sender_spec.rb` | Meta API POST shape, `external_id` return |
| `spec/e2e/pipeline_spec.rb` | LocalStack SQS → Consumer → live Rails → DB assertion |

**`Parser`:**
- Reads Meta's payload (`entry[0].changes[0].value.messages[0]` nesting).
- Text (`messages[0].type == "text"`) → Common Ingestion Payload with `content_type: "text"`, `content: messages[0].text.body`, `attachments: []`.
- Status updates (`entry[0].changes[0].value.statuses[0]`) → `outbound_status_update` payload.
- Everything else: raise `FaleComChannel::UnsupportedContentTypeError` (wired to NACK → DLQ for later manual handling while media types are not implemented).
- Puts `business_account_id` + `phone_number_id` in `metadata.whatsapp_context`.

**`SignatureVerifier`:**
- Constant-time compare of `X-Hub-Signature-256` against HMAC-SHA256 of the raw body using the Meta app secret.
- Raises `FaleComChannel::SignatureError` on failure → Consumer NACKs.

**`Sender`:**
- POSTs to `https://graph.facebook.com/v21.0/{phone_number_id}/messages` with `{messaging_product: "whatsapp", to, text: {body}}`.
- Returns `{ external_id: response["messages"][0]["id"] }`.
- Pulls `access_token` + `phone_number_id` from `channel.credentials` (passed through in the `/send` payload metadata by Rails in Spec 05) or `ENV["WHATSAPP_ACCESS_TOKEN"]` for the dev path.
- Text-only — any `content_type` other than `text` raises `NotImplementedError` for Plan 04.

**Target size:** ~250 lines including specs.

### 2.8 `infra/dev-webhook/` — Local API Gateway Mock

Tiny Roda app, dev-only. Receives POSTs at `/webhooks/:channel_type`, body forwarded to the matching LocalStack SQS queue.

**Files:**

| File | Purpose |
|---|---|
| `app.rb` | Roda app — `POST /webhooks/:channel_type → enqueue(raw_body)` |
| `config.ru` | Rackup entry |
| `Gemfile` | `roda`, `aws-sdk-sqs`, `puma` |
| `Dockerfile` | Container image |
| `spec/app_spec.rb` | rack-test: posts end up on the right queue |

**Routing:**
- `POST /webhooks/whatsapp-cloud` → enqueue to `sqs-whatsapp-cloud` on LocalStack.
- `POST /webhooks/zapi` → enqueue to `sqs-zapi`. (Queue may not have a consumer in Plan 04 — that's fine; message sits until Z-API container ships in a later plan.)
- Unknown `channel_type` → 404.

**Env:** `AWS_REGION`, `AWS_ACCESS_KEY_ID=test`, `AWS_SECRET_ACCESS_KEY=test`, `AWS_ENDPOINT_URL_SQS=http://localstack:4566`.

**No HMAC, no DB, no Rails dependency.** ~60 lines.

### 2.9 `infra/docker-compose.yml` Updates

- **Add** `localstack` service (image `localstack/localstack:3`, `SERVICES=sqs`, port `4566`).
- **Uncomment** `app`, `app-jobs`, `dev-webhook`, `channel-whatsapp-cloud` services.
- **Env vars** match the rewrite in `ARCHITECTURE.md § infra/docker-compose.yml` (already updated in the v2 hardening PR):
  - Containers: `SQS_QUEUE_NAME`, `AWS_REGION=us-east-1`, `AWS_ACCESS_KEY_ID=test`, `AWS_SECRET_ACCESS_KEY=test`, `AWS_ENDPOINT_URL_SQS=http://localstack:4566`, `FALECOM_API_URL=http://app:3000`, `FALECOM_DISPATCH_HMAC_SECRET`.
  - `app`: drops `FALECOM_INGEST_HMAC_SECRET`, keeps `FALECOM_DISPATCH_HMAC_SECRET` + `CHANNEL_WHATSAPP_CLOUD_URL`.
- **Queue seeding:** a `localstack-init` container runs `awslocal sqs create-queue --queue-name sqs-whatsapp-cloud` (and `sqs-zapi`) on startup. Or `packages/app/bin/setup` gains a `rake sqs:ensure_queues` step that uses `Aws::SQS::Client` against the configured endpoint. Spec leaves the choice to the plan.

### 2.10 Developer utilities

Kept — still useful.

**`rake ingest:mock`** — generates a fresh inbound message and calls `Ingestion::ProcessMessage` directly, bypassing the controller and the queue. Smoke test for the Rails side.

**`curl` into `/internal/ingest`** — no HMAC needed, just JSON:

```bash
curl -X POST http://localhost:3000/internal/ingest \
     -H "Content-Type: application/json" \
     -d @test_message.json
```

Works in dev because the Rails app is running on the developer's machine and `/internal/*` is only bound to localhost or the compose network — no public exposure.

**Reference payload (text inbound):**
```json
{
  "type": "inbound_message",
  "channel": {
    "type": "whatsapp_cloud",
    "identifier": "+5511999999999"
  },
  "contact": {
    "source_id": "5511988888888",
    "name": "João Silva",
    "phone_number": "+5511988888888"
  },
  "message": {
    "external_id": "WAMID.12345",
    "direction": "inbound",
    "content": "Olá, gostaria de saber mais sobre o produto.",
    "content_type": "text",
    "attachments": [],
    "sent_at": "2026-04-17T12:00:00Z"
  }
}
```

### 2.11 Tests

- [ ] **`Internal::IngestController` request specs:**
  - Valid inbound message → 200, message created, conversation created, events emitted.
  - Valid status update → 200, message status updated.
  - Unknown channel type/identifier → 422.
  - Schema-invalid payload (e.g. missing `message.external_id`) → 422.
  - Duplicate `external_id` → 200, no second message created, no second event emitted.
  - Status update for unknown `external_id` → 422 (container NACKs, SQS redelivers).

- [ ] **`Ingestion::ProcessMessage` service specs:**
  - New contact + new conversation → creates both, emits `contacts:created`, `contact_channels:created`, `conversations:created`, `messages:inbound`.
  - Existing contact + existing conversation → appends message, emits only `messages:inbound`.
  - Resolved conversation + new message → creates new conversation, emits `conversations:created`.
  - Idempotent on duplicate `external_id` — second call returns same message, emits nothing.

- [ ] **`Contacts::Resolve` specs:**
  - New `(channel, source_id)` with new phone → creates Contact + ContactChannel, emits both events.
  - New `(channel, source_id)` with phone matching existing Contact → reuses Contact, creates ContactChannel, emits only `contact_channels:created`.
  - Existing `(channel, source_id)` → returns existing pair, merges in non-blank new fields without overwriting existing values.

- [ ] **`Conversations::ResolveOrCreate` specs:**
  - Open conversation exists → returned, no event emitted.
  - Only resolved conversations exist → creates new, emits `conversations:created`.
  - No conversations → creates new with status `queued` (no flow) or `bot` (with active flow).
  - Concurrent call simulation (two threads) → both return valid conversations, `display_id`s are distinct consecutive integers, no `PG::UniqueViolation` escapes the service.

- [ ] **`Messages::Create` specs:**
  - Fresh message → inserted, event emitted, `conversation.last_activity_at` bumped.
  - Duplicate `(channel_id, external_id)` → no insert, returns existing record, no event.

- [ ] **WhatsApp Cloud parser specs:**
  - Text message → correct common payload with `content_type: "text"` and `attachments: []`.
  - Status update → correct `outbound_status_update` payload.
  - Unsupported content type (`image`) → raises `FaleComChannel::UnsupportedContentTypeError`.
  - Signature mismatch → `FaleComChannel::SignatureError`.

- [ ] **WhatsApp Cloud sender specs:**
  - Text outbound → correct Meta API POST shape, returns `{ external_id: … }`.
  - Non-text content type → raises `NotImplementedError`.

- [ ] **`dev-webhook` rack-test specs:**
  - `POST /webhooks/whatsapp-cloud` → body lands on `sqs-whatsapp-cloud` queue (LocalStack stub via `aws-sdk-sqs` `stub_responses`).
  - Unknown channel type → 404.

- [ ] **End-to-end integration test — `packages/channels/whatsapp-cloud/spec/e2e/pipeline_spec.rb`:**
  - Spins up Rails in-process (`Rack::Server.start`), points at the test DB.
  - Boots LocalStack queue (or uses `stub_responses` against the adapter's client).
  - Seeds a WhatsApp Cloud channel via `Channel.create!`.
  - Enqueues a real Meta-format webhook JSON onto `sqs-whatsapp-cloud`.
  - Starts the container's consumer loop in a thread.
  - Asserts: inside a 5-second timeout, a Message row exists in the DB with the expected `external_id`, content, and `messages:inbound` event.

---

## 3. What is out of scope?

- **Ingest HMAC.** Rails will not verify HMAC on `/internal/ingest`. See v2 change #1 + ARCHITECTURE § Security.
- **Outbound dispatch.** Agent reply → `SendMessageJob` → container `/send` — Spec 5.
- **Flow engine.** Advancing a bot flow on inbound — Spec 7. Conversations with an active flow are still created with `status: "bot"`, but `Flows::Advance` is not called.
- **Auto-assignment.** Spec 6. Status goes to `queued`, but `Assignments::AutoAssign` is not called.
- **Cross-instance contact dedup.** Multi-WhatsApp-number match across channels of the same type — deferred.
- **Non-text content types.** Image, audio, video, document, location, contact card, interactive (button/list) — deferred. Parser raises `UnsupportedContentTypeError`. Sender raises `NotImplementedError`.
- **`DownloadAttachmentJob`.** Deferred with the non-text types.
- **Other channel containers.** Z-API, Evolution, Instagram, Telegram — separate specs. The `sqs-zapi` queue exists in compose but has no consumer in Plan 04.
- **Terraform / real AWS.** Production infrastructure — separate spec.
- **Channel admin UI.** Seed data is sufficient for Plan 04; admin CRUD ships with workspace UI (Spec 06).
- **Dashboard views.** Conversations and messages appear in the DB and fire Turbo Stream broadcasts; the UI rendering them is its own scope.

---

## 4. What changes about the system?

- Messages can enter the system end-to-end: provider webhook → API Gateway (dev-webhook locally) → SQS → channel container → Rails → DB.
- `/internal/ingest` is live and serves the single known contract.
- `Contacts::Resolve`, `Conversations::ResolveOrCreate`, `Messages::Create`, `Ingestion::ProcessMessage`, `Ingestion::ProcessStatusUpdate` all exist as reviewable, tested services.
- Idempotency via `(channel_id, external_id)` unique index ensures SQS redelivery never creates duplicates.
- The advisory-lock `display_id` generator removes the concurrent-ingestion race deferred from Spec 02 §7.1.
- `packages/channels/whatsapp-cloud/` is the reference container for every future channel: Parser + SignatureVerifier + Sender on top of the `falecom_channel` gem.
- `infra/dev-webhook/` + LocalStack give a realistic local pipeline without AWS creds.
- Turbo Stream broadcasts fire on every inbound message — the dashboard (when it ships) will see real-time updates.

This implements `ARCHITECTURE.md § Inbound Message Flow` (steps 1–10, minus flow advance + auto-assign) and `ARCHITECTURE.md § Build Order → Phase 3`.

---

## 5. Acceptance criteria

1. `POST /internal/ingest` with a valid text `inbound_message` returns 200 and creates a Message row.
2. Same request with unregistered `channel.type + channel.identifier` returns 422 and writes nothing.
3. Schema-invalid payload returns 422.
4. Sending the same `external_id` twice creates exactly one Message and emits exactly one `messages:inbound` event.
5. A brand-new contact arriving on a channel creates a `Contact` + `ContactChannel` pair and emits both events.
6. A contact arriving on a channel whose `phone_number` already matches an existing `Contact` reuses that `Contact` and only emits `contact_channels:created`.
7. A message for a contact_channel with no open conversation creates one with the correct `status` (`bot` if flow configured, else `queued`) and emits `conversations:created`.
8. WhatsApp Cloud parser correctly transforms a real Meta text webhook into the Common Ingestion Payload (attachments `[]`, `content_type` `"text"`, metadata `whatsapp_context` populated).
9. WhatsApp Cloud sender correctly calls `graph.facebook.com/v21.0/{phone_number_id}/messages` with a text body and returns `{external_id: …}`.
10. `dev-webhook` routes `POST /webhooks/whatsapp-cloud` to the `sqs-whatsapp-cloud` queue on LocalStack.
11. End-to-end test: a real Meta webhook JSON pushed to `dev-webhook` ends up as a persisted `Message` + emitted `messages:inbound` event within a 5-second timeout.
12. `bundle exec rspec` in `packages/app`, `packages/channels/whatsapp-cloud`, `packages/falecom_channel`, and `infra/dev-webhook` all pass.
13. `bundle exec standardrb` passes across every package.

---

## 6. Risks

- **Meta webhook format drift.** Meta occasionally mutates their payload shape. Mitigation: the parser is a single file; its tests pin today's shape; `raw` preserves the original byte-for-byte for forensic replay.
- **LocalStack behavioral drift from real SQS.** LocalStack's SQS implementation is mature but not byte-identical to AWS. Mitigation: the same `aws-sdk-sqs` client is used in dev, CI, and prod — only the endpoint URL changes. Production behavior is verified manually in staging before first real deploy.
- **Rails-in-process in the e2e test.** Booting Rails inside the container's spec suite is heavier than a pure unit test. Mitigation: only one spec file does this, tagged `:e2e` so it can be excluded from fast local runs (`rspec --exclude-tag e2e`). CI runs it.
- **Transaction scope of `ProcessMessage`.** Wrapping contact + conversation + message creation in a single transaction is clean but serializes display_id assignment. Mitigation: the transaction hits Postgres only — no external HTTP inside the lock. Advisory lock is transaction-scoped so it auto-releases.

---

## 7. Decided (was "Open Questions")

1. **Conversation reopening** — when a contact messages after a resolved conversation, a fresh conversation is created. Simpler analytics, simpler state machine for v1.
2. **WhatsApp Cloud API version** — pinned to `v21.0`. Meta rolls versions forward; we move deliberately.
3. **Queue backend** — SQS only (Plan 03 decision). Dev runs against LocalStack; the same adapter works.
4. **Ingest authentication** — none at the app layer (v2 hardening). Ingress topology + Channel lookup + idempotency index are the defenses.
