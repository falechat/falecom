# Spec: Outbound Dispatch

> **Phase:** 4 (Outbound)
> **Execution Order:** 5 of 7 — after Spec 4
> **Date:** 2026-04-17
> **Status:** Draft — awaiting approval
> **Depends on:**
> - [Spec 2: Core Domain Models](./02-core-domain-models.md) (Message model exists)
> - [Spec 3: falecom_channel Gem](./03-falecom-channel-gem.md) (SendServer, HMAC, Payload exist)
> - [Spec 4: Ingestion Pipeline](./04-ingestion-pipeline.md) (IngestController, WhatsApp container exist)

---

## 1. What problem are we solving?

Messages can enter the system (Spec 4) but cannot leave it. Agents have no way to reply. The outbound path — from agent keystroke to provider delivery confirmation — is the other half of the messaging loop.

This spec covers:
- Agent composing and sending a reply in the dashboard.
- The reply being persisted, queued, and dispatched to the correct channel container.
- The channel container translating the common outbound payload into a provider API call.
- Delivery status updates (sent/delivered/read/failed) flowing back through the existing inbound pipeline and updating checkmarks in the dashboard.
- Retry and failure handling when provider calls fail.

---

## 2. What is in scope?

### 2.1 Dashboard — Reply Form

A Turbo Frame-based reply form at the bottom of the conversation detail view.

- [ ] **Reply input** — textarea with submit button. Supports text messages only in v1 (attachments are a follow-up).
- [ ] **Optimistic rendering** — on submit, the agent sees their own message in the thread immediately (via Turbo Stream), before the provider confirms delivery. The message appears with `status: pending` (no checkmarks yet).
- [ ] **Form target** — `POST /dashboard/conversations/:id/messages`.
- [ ] **Controller**:
  ```
  Dashboard::MessagesController#create
    → authorize (current_user can reply to this conversation)
    → Dispatch::Outbound.call(conversation:, content:, content_type: "text", actor: current_user)
    → respond with Turbo Stream append to message list
  ```

### 2.2 `Dispatch::Outbound` Service

The single service for all outbound messages — used by agent replies, flow engine responses, system messages, and future API.

```ruby
class Dispatch::Outbound
  def self.call(conversation:, content:, content_type: "text", attachments: [], metadata: {}, actor:, reply_to_external_id: nil)
    message = Messages::Create.call(
      conversation: conversation,
      direction: "outbound",
      content: content,
      content_type: content_type,
      status: "pending",
      sender: actor,
      metadata: metadata,
      reply_to_external_id: reply_to_external_id
    )

    # Broadcast immediately — agent sees their message right away
    broadcast_message(message)

    # CRITICAL: Enqueue AFTER the transaction commits.
    # If enqueued inside the transaction, Solid Queue workers may pick up the
    # job before the Message row is visible, causing RecordNotFound → silent loss.
    ActiveRecord::Base.after_all_transactions_committed do
      SendMessageJob.perform_later(message.id)
    end

    message
  end
end
```

Key behaviors:
- Creates the `Message` record with `status: pending` and `direction: outbound`.
- Sets `sender_type` / `sender_id` based on the actor (User, Bot, System).
- Broadcasts via Turbo Stream so the sender (and any other viewers of the conversation) see the message immediately.
- Enqueues `SendMessageJob` for async delivery.
- Emits `messages:outbound` event.

### 2.3 `SendMessageJob`

Solid Queue background job that dispatches the message to the correct channel container.

```ruby
class SendMessageJob < ApplicationJob
  queue_as :outbound
  retry_on Faraday::Error, wait: :polynomially_longer, attempts: 5
  discard_on ActiveRecord::RecordNotFound

  def perform(message_id)
    message = Message.find(message_id)
    return if message.status == "sent" # already sent (idempotent)

    channel = message.channel
    container_url = container_url_for(channel.channel_type)

    payload = build_outbound_payload(message)

    response = FaleComChannel::DispatchClient.new(
      container_url: container_url
    ).send_message(payload)

    message.update!(
      external_id: response["external_id"],
      status: "sent"
    )

    # Emit messages:sent — this is the synchronous confirmation from the provider.
    # If the provider also sends a `sent` status webhook later,
    # ProcessStatusUpdate's idempotency guard will skip the duplicate.
    Events::Emit.call(
      name: "messages:sent",
      subject: message,
      actor: :system
    )

    broadcast_message_status(message)
  rescue Faraday::Error => e
    # Retry will be handled by Solid Queue
    raise
  rescue => e
    message.update!(status: "failed", error: e.message)
    Events::Emit.call(name: "messages:failed", subject: message, actor: :system)
    broadcast_message_status(message)
    # Don't re-raise — message is permanently failed
  end
end
```

**Container URL resolution:**
```ruby
def container_url_for(channel_type)
  ENV.fetch("CHANNEL_#{channel_type.upcase}_URL")
  # e.g., CHANNEL_WHATSAPP_CLOUD_URL=http://channel-whatsapp-cloud:9292
end
```

**Outbound payload construction:**
```ruby
def build_outbound_payload(message)
  {
    type: "outbound_message",
    channel: {
      type: message.channel.channel_type,
      identifier: message.channel.identifier
    },
    contact: {
      source_id: message.conversation.contact_channel.source_id
    },
    message: {
      internal_id: message.id,
      content: message.content,
      content_type: message.content_type,
      attachments: [], # v1: text only
      reply_to_external_id: message.reply_to_external_id
    },
    metadata: message.metadata
  }
end
```

### 2.4 WhatsApp Cloud Container — `/send` Endpoint

Extends the WhatsApp Cloud container (built in Spec 4) with the outbound path.

```ruby
class WhatsappCloudSendServer < FaleComChannel::SendServer
  def handle_send(payload)
    sender = Sender.new(
      access_token: ENV.fetch("WHATSAPP_ACCESS_TOKEN"),
      phone_number_id: resolve_phone_number_id(payload)
    )
    sender.send_message(payload)
  end
end
```

**`Sender`:**
- Maps common outbound payload → Meta Cloud API format.
- `content_type: "text"` → `{ messaging_product: "whatsapp", to: source_id, type: "text", text: { body: content } }`.
- POSTs to `https://graph.facebook.com/v21.0/{phone_number_id}/messages`.
- Returns `{ external_id: response["messages"][0]["id"] }`.
- Handles Meta API errors (rate limit, invalid number, etc.) with structured error responses.

**`phone_number_id` resolution:**
- Channel credentials (stored encrypted in the `channels` table) include `phone_number_id`.
- For v1, the container reads this from ENV (`WHATSAPP_PHONE_NUMBER_ID`). Future: passed in the `/send` payload metadata.

### 2.5 Delivery Status Updates — Closing the Loop

Status updates (sent → delivered → read → failed) arrive as webhooks from the provider. The path:

```
Provider → API Gateway → SQS → channel container (parses as outbound_status_update)
→ POST /internal/ingest → Ingestion::ProcessStatusUpdate (built in Spec 4)
→ message.status updated → Turbo Stream broadcast → checkmarks update in dashboard
```

This path already exists from Spec 4. This spec ensures:

- [ ] The WhatsApp Cloud container parser handles status webhook payloads (`entry[0].changes[0].value.statuses[0]`) and produces `outbound_status_update` common payloads.
- [ ] The `Ingestion::ProcessStatusUpdate` service (from Spec 4) correctly updates statuses and broadcasts.
- [ ] Status progression is enforced: `pending → sent → delivered → read`. A `delivered` status doesn't overwrite a `read` status. `failed` can arrive at any point.

### 2.6 Dashboard — Message Status Display

Messages in the conversation thread show delivery status indicators:

| Status | Visual |
|---|---|
| `pending` | Clock icon (gray) |
| `sent` | Single checkmark (gray) |
| `delivered` | Double checkmark (gray) |
| `read` | Double checkmark (blue) |
| `failed` | Error icon (red) + error message on hover |

These update in real-time via Turbo Stream replacements targeting the message's status element.

### 2.7 Solid Queue Configuration

```yaml
# config/queue.yml
queues:
  - name: default
    threads: 5
  - name: outbound
    threads: 3
    polling_interval: 1
```

The `outbound` queue runs with separate thread count to avoid starving other jobs.

### 2.8 Tests

- [ ] **`Dispatch::Outbound` service specs:**
  - Creates Message with `status: pending`, `direction: outbound`.
  - Enqueues `SendMessageJob`.
  - Emits `messages:outbound` event.

- [ ] **`SendMessageJob` specs:**
  - Successful send → updates `external_id` and `status: sent`.
  - Provider returns error → retries via Solid Queue.
  - Max retries exhausted → `status: failed`, error recorded.
  - Already sent (`status: sent`) → no-op (idempotent).

- [ ] **`Dashboard::MessagesController` request specs:**
  - Agent creates reply → 200, message appears in DB with correct attributes.
  - Unauthorized user → 403.
  - Turbo Stream response includes message append.

- [ ] **WhatsApp Cloud Sender specs:**
  - Correct Meta API call format for text message.
  - Returns `external_id` from Meta response.
  - Handles Meta rate limit error.

- [ ] **Status update flow specs:**
  - Status webhook → container parses → `/internal/ingest` → message status updated.
  - Status progression enforced (no backward movement).

- [ ] **End-to-end outbound test:**
  - Agent sends reply → message in DB → `SendMessageJob` POSTs to container → container calls provider (mocked) → `external_id` saved → status update webhook → status updated to `delivered`.

---

## 3. What is out of scope?

- **Attachment sending** — text-only in v1. Outbound attachments are a follow-up spec.
- **Template messages** — WhatsApp template sending (HSM) is on the roadmap.
- **Rate limiting** — per-channel outbound rate limiting is deferred to when we have real traffic data.
- **Circuit breaker** — backpressure when a container is down is an open question in the architecture.
- **Other channel containers' send endpoints** — only WhatsApp Cloud in this spec.
- **Flow engine outbound** — `Flows::Advance` will call `Dispatch::Outbound` but is not wired here.

---

## 4. What changes about the system?

After this spec:

- Agents can reply to conversations in the dashboard.
- Messages flow from agent → Rails → Solid Queue → channel container → provider → contact.
- Delivery statuses flow back and update checkmarks in real-time.
- Failed sends are retried automatically and surfaced to the agent.
- The full bidirectional messaging loop is complete for WhatsApp Cloud.

This implements `ARCHITECTURE.md § Outbound Message Flow` (steps 1–9) and `ARCHITECTURE.md § Build Order → Phase 4`.

---

## 5. Acceptance criteria

1. Agent types a reply and clicks Send → message appears in the thread immediately with a clock icon.
2. `SendMessageJob` runs and POSTs to the WhatsApp container → message status changes to `sent` (single checkmark).
3. Provider sends `delivered` status webhook → double checkmark appears.
4. Provider sends `read` status webhook → blue double checkmark appears.
5. If the provider call fails after max retries → message shows error icon with error text.
6. Sending the same message job twice (Solid Queue redelivery) does not send duplicate messages to the provider.
7. Unauthorized users cannot send messages to conversations they don't have access to.
8. `bundle exec rspec` passes across all packages.

---

## 6. Risks

- **Provider API latency** — Meta Cloud API can be slow (1–5s). `SendMessageJob` handles this asynchronously, but the agent may wonder why checkmarks take time. Mitigation: the optimistic rendering (pending status shown immediately) sets the right expectation.
- **Container URL misconfiguration** — if `CHANNEL_WHATSAPP_CLOUD_URL` is wrong or the container is down, all outbound messages fail. Mitigation: the `/health` endpoint on containers can be monitored; failed messages surface clearly in the dashboard.

---

## 7. Open questions

1. **Outbound queue priority** — Should outbound messages from agents have higher priority than bot-generated messages (from the flow engine)? Recommendation: same priority for v1; add priority queues if bot volume causes agent reply delays.
2. **Message editing** — Can an agent edit a sent message? WhatsApp Cloud API doesn't support this. Recommendation: no editing in v1.
3. **Phone number ID resolution** — For WhatsApp, we need `phone_number_id` to send. Should this come from `channel.credentials`, from ENV, or from the `/send` payload metadata? Recommendation: `channel.credentials` (already encrypted). The sender can access it via metadata passed in the outbound payload, avoiding ENV per-channel proliferation.
