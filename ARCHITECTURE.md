# FaleCom — Architecture

> Source of truth. Update when the architecture changes — not before, not after.

---

## What is FaleCom

FaleCom ("Fale Com" — talk with) is an open-source omnichannel communication platform built for small and medium businesses. It is a **standalone Rails 8.1 application** — a single, focused codebase that owns the full domain: contacts, conversations, messages, users, teams, flows, and the agent workspace.

Around it sits a queue-first ingestion pipeline: a managed AWS API Gateway in front of per-channel SQS queues, and tiny channel containers that translate provider-specific payloads into a single common ingestion format.

The goal is to give developers a fair-priced, self-hostable platform they can set up for SMB clients without burning nights of sleep dealing with webhook spikes, lost messages, or fragile integrations — and without the complexity of a large legacy messaging platform underneath.

---

## Core Decisions

| Decision | Choice | Reason |
|---|---|---|
| Main application | Ruby on Rails 8.1 | Single codebase owns domain, API, dashboard, real-time, and background jobs |
| Language across stack | Ruby | Single mental model. Rails for the monolith, Roda for thin services |
| Database | Postgres (single instance, single schema) | Source of truth for everything |
| Background jobs | Solid Queue | Rails 8 default, Postgres-backed, zero extra infra |
| Real-time / WebSocket | Solid Cable | Rails 8 default, Postgres-backed, zero extra infra |
| Cache | Solid Cache | Rails 8 default. Complete Solid trio |
| Authentication | Rails 8 built-in generator | `has_secure_password` + session cookies. Simple, no Devise bloat |
| UI layer | Hotwire (Turbo + Stimulus) | Turbo Streams for real-time. Turbo Frames for partial updates |
| Component library | JR Components (ui.jetrockets.com) + ViewComponent | ViewComponent-based, TailwindCSS 4, Stimulus. Copy/paste/customize — components owned in the repo, no version lock |
| CSS | TailwindCSS 4 | Required by JR Components. Semantic design tokens + dark mode built-in |
| Asset pipeline | Vite (via `vite_rails`) | Required by JR Components. Faster builds, HMR, better JS/CSS ecosystem than importmap for this stack |
| Inbound buffer | AWS SQS (prod) / local queue (dev) | Decouples channel spikes from processing |
| Per-channel queues | One SQS queue per channel type | Channels scale independently. Failures isolated per channel |
| API Gateway | AWS API Gateway (managed) | Receives all provider webhooks, validates, pushes directly to the correct SQS queue. No code we maintain — just routes and mapping templates |
| Channel containers | Tiny Roda apps (one per channel type) | Stateless translators. Pull from SQS, normalize, POST to API |
| Inbound contract | Common ingestion payload | Single schema the API accepts. Each channel container produces it |
| Outbound dispatch | HTTP + Solid Queue retries | Rails enqueues job → job POSTs to channel container `/send` endpoint |
| Flow Engine | Inline Ruby service | No webhook roundtrip. Flow advances inside the ingestion transaction |
| Flow builder UI | Simple Rails forms (v1) | Visual canvas on roadmap |
| API surface (external) | Intentional, explicit | Only `/internal/ingest` (HMAC-auth), public `/api/v1/*` (future), `/mcp/*` (future) |
| Internal API access | Server-side Rails controllers | Dashboard renders HTML. No JSON proxy layer inside the monolith |
| Deployment | Docker Compose | Single compose file for dev. Each service scales independently in prod |
| ORM | ActiveRecord | Rails default |
| Multi-tenancy | Account-scoped at the model level | Single-tenant in v1 but FK present for future growth |

---

## Glossary

| Term | Definition |
|---|---|
| **FaleCom** | The platform. "Fale Com" = talk with (Portuguese) |
| **Account** | Tenant boundary. Everything belongs to an account |
| **User** | Internal person using the platform — agent, admin, supervisor |
| **Contact** | The person interacting with the business via a channel. Not a user |
| **Channel** | A registered provider instance — a specific WhatsApp number, Instagram account, Telegram bot, etc. Identified by `channel_type` + `identifier`. "WhatsApp Vendas" and "WhatsApp Suporte" are two distinct Channels, both of `channel_type: whatsapp_cloud`. Holds credentials, auto-assign policy, the active flow, and is where messages arrive |
| **Channel Container** | A tiny Roda app that pulls from a channel's SQS queue, parses the provider-specific payload, and POSTs it to the API in the common ingestion format |
| **ContactChannel** | Join between a Contact and a Channel, holding the `source_id` (WhatsApp number, Instagram PSID, etc). Routes messages to the correct conversation |
| **Workspace** | UI term only. The filtered view of conversations a logged-in user has access to — composed of the Channels their Teams attend. Not a database entity. Users see sub-views within: "Mine", "Unassigned", "My team", "By channel" |
| **Conversation** | A thread of messages between a contact and the team on one channel. Has a status and an assignee |
| **Message** | A single message in a conversation. Has direction (inbound/outbound), content type, and status |
| **Team** | A group of users. Conversations can be routed to teams |
| **Role** | Permission set assigned to a user: admin, supervisor, agent |
| **Flow** | A stateful conversational script run by the bot before handoff. Composed of nodes |
| **Node** | A step in a flow. Sends a message, shows a menu, collects input, or triggers handoff |
| **Handoff** | Specifically: the moment a flow transfers a conversation to a human (bot → queued). Distinct from human-to-human Transfer |
| **Transfer** | Moving an ongoing conversation between assignees or teams. Three cases: reassign (User → User), team transfer (Team A → Team B), unassign (back to queue). All emit `conversations:transferred` |
| **Gateway** | AWS API Gateway (managed service). Receives provider webhooks, validates, and pushes raw payloads directly to the correct SQS queue. No code we write or maintain |
| **Channel Registration** | A row in the `channels` table that tells the API how to recognize and route messages of a given type. The API refuses to ingest messages for channels that aren't registered |
| **Common Ingestion Payload** | The single normalized message format the API accepts at `/internal/ingest`. Every channel container produces this format. Has required common fields (`channel_type`, `channel_identifier`, `contact`, `message`) and a flexible `metadata` field for provider-specific extras |
| **Conversation status** | `bot` (flow active), `queued` (waiting for agent), `assigned` (agent working), `resolved` |
| **Event** | An auditable action that happened. Module-prefixed, past-tense: `conversations:created`, `flows:handoff`, `messages:inbound`. Every state change in the system emits at least one. Append-only, immutable |
| **Audit-by-default** | Architectural principle: every state-changing action is recorded as an Event. State mutations happen only in Services, and every Service emits its events |
| **MCP** | Model Context Protocol. Future module to expose FaleCom as a tool for AI agents |
| **Solid Queue** | Rails 8 Postgres-backed background job system |
| **Solid Cable** | Rails 8 Postgres-backed WebSocket pub/sub |
| **Solid Cache** | Rails 8 Postgres-backed cache store |
| **ViewComponent** | GitHub's component framework for Rails. Components are Ruby classes + ERB/Haml templates, testable in isolation |
| **JR Components** | Jetrockets' open-source Rails UI library (ui.jetrockets.com). ViewComponent + TailwindCSS 4 + Stimulus. Copy/paste into the repo — no gem dependency, no version lock |
| **`falecom_channel`** | Internal Ruby gem shared by every channel container. Provides the SQS consumer loop, the Common Ingestion Payload schema, the HMAC-authenticated Rails ingest client, and the Roda base server for `/send`. Path-based dependency in the monorepo |

---

## Architecture

### Layers

```
┌──────────────────────────────────────────────────────────┐
│                        CHANNELS                          │
│   WhatsApp Cloud · Z-API · Evolution · Instagram · ...   │
│                                                          │
│   Each provider is configured in its own console         │
│   (Meta Developer Portal, Z-API panel, etc.) to POST     │
│   webhooks to a channel-specific path on the             │
│   managed API Gateway:                                   │
│                                                          │
│     /webhooks/whatsapp-cloud                             │
│     /webhooks/zapi                                       │
│     /webhooks/evolution                                  │
│     /webhooks/instagram                                  │
│     /webhooks/telegram                                   │
└──────────────────────────┬───────────────────────────────┘
                           │ HTTPS POST
┌──────────────────────────▼───────────────────────────────┐
│     LAYER 1 — AWS API GATEWAY + SQS (managed)            │
│                                                          │
│  AWS API Gateway:                                        │
│   · one route per channel type                           │
│   · returns 200 immediately                              │
│   · pushes raw body directly to the channel's SQS queue  │
│     (via API Gateway → SQS integration / VTL mapping)    │
│   · handles hub.challenge GET verification via a simple  │
│     route response (no Lambda needed)                    │
│                                                          │
│  No code we maintain in this layer. Configured as        │
│  infrastructure (Terraform / SAM / CDK).                 │
│                                                          │
│  One SQS queue per channel type:                         │
│    sqs-whatsapp-cloud · sqs-zapi · sqs-evolution ·       │
│    sqs-instagram · sqs-telegram                          │
│                                                          │
│  Channel signature validation happens in Layer 2.        │
│  The raw payload is kept intact through this layer.      │
└────────────────────────┬─────────────────────────────────┘
                         │ pulled per-channel
┌────────────────────────▼─────────────────────────────────┐
│          LAYER 2 — CHANNEL CONTAINERS (Roda)             │
│                                                          │
│   whatsapp-cloud · zapi · evolution · instagram ·        │
│                     telegram                             │
│                                                          │
│   Each container is a tiny Roda app that:                │
│   · pulls from its own SQS queue (stateless worker)      │
│   · validates the provider signature on the raw payload  │
│   · parses the provider-specific format                  │
│   · normalizes to the Common Ingestion Payload:          │
│        - required common fields                          │
│        - provider-specific extras in `metadata`          │
│   · POSTs to Rails /internal/ingest with HMAC signature  │
│   · exposes /send endpoint for outbound dispatch         │
│                                                          │
│   Stateless. No database. No domain logic.               │
│   A new channel = a new container + a new route in       │
│   API Gateway + a new SQS queue.                         │
└────────────────────────┬─────────────────────────────────┘
                         │ POST /internal/ingest
                         │ (HMAC-signed, JSON)
┌────────────────────────▼─────────────────────────────────┐
│            LAYER 3 — FALECOM APP (Rails 8.1)             │
│        Hotwire · ViewComponent · JR Components · Vite    │
│                                                          │
│  Controllers:                                            │
│    · Internal::IngestController (HMAC-auth)              │
│        - looks up the Channel by type + identifier       │
│        - rejects if channel is not registered            │
│        - dispatches to Ingestion::ProcessMessage         │
│    · Dashboard::* (Hotwire views)                        │
│    · Api::V1::* (future public API)                      │
│    · Mcp::* (future AI agent access)                     │
│                                                          │
│  Services:                                               │
│    · Ingestion::ProcessMessage                           │
│    · Contacts::Resolve                                   │
│    · Conversations::ResolveOrCreate                      │
│    · Messages::Create                                    │
│    · Flows::Advance                                      │
│    · Dispatch::Outbound                                  │
│    · Assignment::AutoAssign                              │
│                                                          │
│  Background jobs (Solid Queue):                          │
│    · SendMessageJob → POST to channel container /send    │
│    · ApplyAutomationRulesJob                             │
│    · AutoResolveStaleConversationsJob                    │
│    · DownloadAttachmentJob                               │
│                                                          │
│  Real-time (Solid Cable):                                │
│    · Turbo::StreamsChannel (workspace view, conversation list)│
│    · ConversationChannel                                 │
│                                                          │
│  Postgres (single schema):                               │
│    · accounts, users, teams, team_members, channels,     │
│      channel_teams                                       │
│    · contacts, contact_channels, conversations, messages │
│    · flows, flow_nodes, conversation_flows               │
│    · automation_rules, events                            │
│    · sessions                                            │
│    · solid_queue_*, solid_cable_*, solid_cache_*         │
└────────────────────────┬─────────────────────────────────┘
                         │ outbound dispatch
                         │ (SendMessageJob → HTTP POST)
                         ▼
┌──────────────────────────────────────────────────────────┐
│      LAYER 2 (outbound) — CHANNEL CONTAINERS /send       │
│   · call provider API (WhatsApp Cloud, Z-API, etc)       │
│   · provider returns delivery status via webhook,        │
│     which re-enters the same inbound pipeline            │
│     (Layer 1 → Layer 2 → Layer 3)                        │
└──────────────────────────────────────────────────────────┘
```

---

## Inbound Message Flow

```
1. Contact sends message on WhatsApp
2. Meta POSTs webhook → AWS API Gateway /webhooks/whatsapp-cloud
3. API Gateway:
   · returns 200 immediately
   · pushes raw body directly to sqs-whatsapp-cloud (direct SQS integration)
4. whatsapp-cloud channel container pulls from sqs-whatsapp-cloud
5. Container validates the Meta signature on the raw payload
6. Container parses Meta payload, normalizes to Common Ingestion Payload
7. Container POSTs to Rails /internal/ingest with HMAC signature
8. Rails Internal::IngestController:
   · verifies HMAC + timestamp
   · looks up Channel by (channel.type, channel.identifier) — rejects if unknown
   · hands off to Ingestion::ProcessMessage
9. Ingestion::ProcessMessage runs inside a transaction:
   · Contacts::Resolve → find or create contact + contact_channel
   · Conversations::ResolveOrCreate → find open conversation or create new
   · Messages::Create → persist the inbound message (with metadata + raw)
   · If conversation.status == "bot" and channel has a flow:
       Flows::Advance → evaluate node, send reply via Dispatch::Outbound
   · If conversation.status == "queued" and auto-assign is on:
       Assignment::AutoAssign → pick agent/team
   · Events.emit("messages:inbound", message)
   · Turbo::StreamsChannel.broadcast_* → dashboard updates in real-time
10. Dashboard updates via Solid Cable → agent sees the message instantly
```

## Outbound Message Flow

```
1. Agent types reply in dashboard, clicks Send
2. Rails creates outbound Message (status: "pending")
3. Rails broadcasts Turbo Stream → the agent sees their own message immediately
4. Rails enqueues SendMessageJob (Solid Queue)
5. SendMessageJob picks up the message, looks up the channel container URL
   for the message's channel_type, POSTs to {container}/send with:
     · HMAC signature (FALECOM_DISPATCH_HMAC_SECRET)
     · outbound payload (channel, contact.source_id, message, metadata)
6. Channel container calls provider API (WhatsApp Cloud, Z-API, etc),
   returns { external_id } synchronously to Rails
7. Rails updates message.external_id and status ("sent")
8. Later, provider sends delivery/read webhooks — these re-enter via the
   same inbound pipeline:
     provider → AWS API Gateway → SQS → channel container →
     /internal/ingest (type=outbound_status_update, with external_id) →
     Rails updates message.status → Turbo Stream → checkmarks update
9. On failure at step 6: SendMessageJob retries with Solid Queue exponential
   backoff. After max retries, message.status = "failed", dashboard shows error.
```

---

## Common Ingestion Payload

This is the **single contract** between channel containers and Rails. Every channel container produces this format. Adding a new channel = writing a new container that produces this payload.

### Design principles

1. **Required common fields** are the same across all channels. The API uses them to identify the channel, contact, conversation, and message — always in the same place.
2. **`metadata`** is a free-form object for provider-specific data the common fields can't express (WhatsApp context, Instagram story references, Telegram reply threading, quoted messages, button payloads, etc.). The API stores it verbatim and passes it through to automation rules and flows.
3. **`raw`** is the original provider payload, kept for audit and debugging. Not used for business logic.
4. The API **rejects** any payload whose `channel.type` + `channel.identifier` doesn't match a registered, active `Channel` row in the database.

### Inbound message

```json
{
  "type": "inbound_message",

  "channel": {
    "type": "whatsapp_cloud",
    "identifier": "5511999999999"
  },

  "contact": {
    "source_id": "5511888888888",
    "name": "João Silva",
    "phone_number": "+5511888888888",
    "email": null,
    "avatar_url": "https://..."
  },

  "message": {
    "external_id": "wamid.HBgLN...",
    "direction": "inbound",
    "content": "Oi, bom dia",
    "content_type": "text",
    "attachments": [],
    "sent_at": "2026-04-16T14:32:00Z",
    "reply_to_external_id": null
  },

  "metadata": {
    "whatsapp_context": {
      "business_account_id": "123...",
      "phone_number_id": "456..."
    },
    "forwarded": false,
    "quoted_message": null
  },

  "raw": { "...": "original provider payload for audit" }
}
```

### Required common fields (reject if missing)

| Field | Notes |
|---|---|
| `type` | `inbound_message`, `outbound_status_update`, or `outbound_echo` |
| `channel.type` | Must match a registered Channel type (`whatsapp_cloud`, `zapi`, `evolution`, `instagram`, `telegram`, ...) |
| `channel.identifier` | Phone number, page ID, bot username — whatever uniquely identifies this channel instance |
| `contact.source_id` | Provider-scoped unique ID for the contact (WhatsApp number, Instagram PSID, Telegram user ID) |
| `message.external_id` | Provider's message ID. Used for idempotency and delivery status correlation |
| `message.direction` | `inbound` or `outbound` |
| `message.content_type` | See table below |
| `message.sent_at` | ISO 8601 timestamp from the provider |

### Optional common fields

| Field | Notes |
|---|---|
| `contact.name`, `contact.phone_number`, `contact.email`, `contact.avatar_url` | Whatever the provider gave us. The API merges these into the Contact record |
| `message.content` | Text or caption. May be empty for attachment-only messages |
| `message.attachments` | Array of attachment objects (see below) |
| `message.reply_to_external_id` | If this message replies to a specific earlier one |

### `metadata` — flexible provider extras

Anything the common schema can't express goes here. Rails stores it on the message record as JSONB. Rules of thumb:

- Don't put things in `metadata` that could be lifted into a common field useful for other providers — those belong in the schema.
- Prefix keys that are clearly provider-specific with the provider name (`whatsapp_context`, `telegram_forward_from`) so the origin is obvious.
- Keep it reasonably flat — nested one level deep is fine, three levels deep is a smell.

### Supported `content_type` values

| Value | Notes |
|---|---|
| `text` | Plain text in `content` |
| `image` | `content` = caption, attachments = 1 image |
| `audio` | Voice note or audio file |
| `video` | Video with optional caption |
| `document` | PDF, doc, etc |
| `location` | `content` = JSON with lat/lng |
| `contact_card` | vCard |
| `input_select` | Interactive menu reply (selected option in `metadata.selection`) |
| `button_reply` | Interactive button reply (button payload in `metadata.button`) |
| `template` | Template message (outbound only, WhatsApp) |

### Attachment structure

```json
{
  "external_url": "https://...",
  "content_type": "image/jpeg",
  "file_size": 123456,
  "filename": "photo.jpg",
  "metadata": { "...": "provider-specific attachment fields" }
}
```

Channel containers pass the provider's media URL. The API enqueues a `DownloadAttachmentJob` (Solid Queue) that fetches the file and stores it via Active Storage asynchronously — the ingest path stays fast.

### Outbound status update

Same endpoint, different `type`:

```json
{
  "type": "outbound_status_update",
  "channel": {
    "type": "whatsapp_cloud",
    "identifier": "5511999999999"
  },
  "external_id": "wamid.HBgLN...",
  "status": "delivered",
  "timestamp": "2026-04-16T14:32:05Z",
  "error": null,
  "metadata": {}
}
```

`status` values: `sent`, `delivered`, `read`, `failed`.

### Outbound dispatch (Rails → channel container /send)

Rails POSTs this to `{container_url}/send`:

```json
{
  "type": "outbound_message",
  "channel": {
    "type": "whatsapp_cloud",
    "identifier": "5511999999999"
  },
  "contact": {
    "source_id": "5511888888888"
  },
  "message": {
    "internal_id": 12345,
    "content": "Obrigado pelo contato!",
    "content_type": "text",
    "attachments": [],
    "reply_to_external_id": "wamid.HBgLN..."
  },
  "metadata": {
    "template_name": null,
    "template_params": null
  }
}
```

Container returns `{ "external_id": "wamid.HBgXXX..." }` on success so Rails can correlate future status updates.

### Channel registration check on ingest

The `Internal::IngestController` performs this lookup before doing any work:

```ruby
channel = Channel.find_by(
  channel_type: payload.dig("channel", "type"),
  identifier:   payload.dig("channel", "identifier")
)

return head :unprocessable_entity unless channel&.active?
```

A message arriving for a channel that isn't registered is a configuration error (or an attack) — rejected outright. Messages rejected this way end up in the SQS DLQ for investigation.

### Idempotency

`message.external_id` is unique per channel. The `messages` table has a unique index on `(channel_id, external_id)` and inserts use `ON CONFLICT DO NOTHING`, so SQS redelivery never creates duplicates.

---

## Shared Infrastructure — `falecom_channel` gem

Every channel container does the same four infrastructure jobs: pull from SQS, validate the HMAC when talking to Rails, produce a valid Common Ingestion Payload, and expose a `/send` endpoint. Only the *translation* between provider-specific format and the common payload is unique per channel. To avoid copying infrastructure code across five containers, the common parts live in an internal gem, `falecom_channel`, consumed via path in the monorepo.

### What the gem provides

| Module | Purpose |
|---|---|
| `FaleComChannel::Consumer` | SQS polling loop with configurable concurrency, visibility timeout, ack/nack, DLQ config, graceful shutdown |
| `FaleComChannel::Payload` | Common Ingestion Payload schema (dry-struct + dry-validation). Single source of truth for the contract. Changes here ripple to every container via `bundle update` |
| `FaleComChannel::IngestClient` | Faraday client for `POST /internal/ingest`. HMAC signing, timestamp header, retry on 5xx, timeouts, structured logging |
| `FaleComChannel::SendServer` | Roda base app for `/send`. HMAC verification, request logging, standard error responses. Containers mount their own handler inside |
| `FaleComChannel::Logging` | Structured JSON logging helpers with correlation IDs that flow through the whole pipeline |

### What the gem deliberately does NOT provide

- No DSL for parsing provider payloads. Each provider is too different; an abstraction here would either leak or handcuff.
- No abstraction over outbound provider calls. Each provider's API has its own auth, pagination, media upload flow, error shapes. Containers own that fully.
- No test framework. Each container tests itself with plain RSpec.

### Anatomy of a channel container using the gem

```ruby
# packages/channels/whatsapp-cloud/app.rb
require "falecom_channel"
require_relative "lib/parser"
require_relative "lib/signature_verifier"

class WhatsappCloudContainer
  include FaleComChannel::Consumer

  queue_name ENV.fetch("SQS_QUEUE_NAME")
  concurrency Integer(ENV.fetch("CONCURRENCY", 10))

  def handle(raw_body, headers)
    SignatureVerifier.verify!(raw_body, headers)       # channel-specific
    payload = Parser.new(raw_body).to_common_payload   # channel-specific
    FaleComChannel::Payload.validate!(payload)         # from gem
    ingest_client.post(payload)                        # from gem
  end
end
```

The `/send` endpoint looks equally thin — gem handles HMAC + routing, container handles the Meta Graph API call.

### Versioning and release

The gem lives at `packages/falecom_channel/` and is referenced via `gem "falecom_channel", path: "../falecom_channel"` from each channel container's Gemfile. No public publishing. Breaking changes to the Common Ingestion Payload bump the gem's major version and require coordinated updates across all containers — CI enforces that all containers build green before a PR touching the gem can merge.

---

## Conversation Status Lifecycle

Clean, explicit lifecycle we define ourselves:

| Status | Meaning | Who controls it |
|---|---|---|
| `bot` | Flow is active, no human needed | Flow Engine (auto on creation if channel has a flow) |
| `queued` | Waiting for an agent to pick up | Set on handoff from flow, or on new message to a channel with no flow |
| `assigned` | Agent or team has it | Assignment service |
| `resolved` | Done | Agent marks resolved, or auto-resolve job after N days |

Transitions:

```
new conversation
    │
    ├── channel has a flow? → bot
    │       │
    │       └── flow terminal node / agent takes over → queued → assigned
    │
    └── no flow → queued → assigned
                     │
                     └── agent resolves → resolved
                             │
                             └── contact messages again → queued (or bot if flow restart)
```

---

## Inactivity and Flow Restart

Configured per flow (per channel):

```
falecom.flows
  └── inactivity_threshold_hours   ← e.g. 2 for WhatsApp, 24 for Instagram
```

When a new inbound message arrives on a channel with an active flow:

```
Is there an active conversation for this contact_channel?
  → YES and not resolved: append message, let flow advance if status=bot
  → YES and resolved: reopen OR start new conversation (configurable)
  → NO: create new conversation, status=bot, start flow from root node

When starting a flow:
  Look up timestamp of the last inbound message on this contact_channel.
  Time since then > inactivity_threshold_hours?
    → YES: start from root (full menu)
    → NO:  start with "Como posso ajudar?"
```

A single `AutoResolveStaleConversationsJob` runs on a cron schedule (Solid Queue recurring job) and resolves conversations that have been inactive for longer than the account's `auto_resolve_duration` setting. Clean and simple.

---

## Flow Engine

The Flow Engine is just Ruby code in `app/services/flows/`. It runs inline inside the message ingestion transaction — no webhooks, no external callbacks, no network roundtrip.

### Full flow cycle

```
1. Inbound message arrives → Ingestion::ProcessMessage
2. If conversation.status == "bot" and channel has a flow:
     Flows::Advance.call(conversation, message)
3. Flows::Advance:
     · loads ConversationFlow (current_node_id, state)
     · evaluates the node based on message content
     · persists next_node_id and updated state
     · if node has a reply: calls Dispatch::Outbound.call(...)
     · if node is terminal: triggers Flows::Handoff
4. Flows::Handoff:
     · updates conversation.status → "queued" (or "assigned" if team has auto-assign)
     · optionally assigns to team/agent
     · sends optional handoff message via Dispatch::Outbound
5. Dispatch::Outbound creates a Message record + enqueues SendMessageJob
6. SendMessageJob POSTs to the channel container /send endpoint
7. Channel container calls the provider API
```

### Flow endpoints in the Rails app (dashboard)

```
GET    /flows                  ← list
POST   /flows                  ← create
GET    /flows/:id              ← edit (Rails form, not canvas in v1)
PUT    /flows/:id              ← save
POST   /flows/:id/activate     ← associate flow with a channel
DELETE /flows/:id/deactivate   ← remove flow from channel
```

Activating a flow just sets `channel.active_flow_id`. No external registration step.

---

## What FaleCom Owns

Everything. There is no other system in the loop holding domain state.

| Concern | Where |
|---|---|
| Webhook ingestion | AWS API Gateway (managed, configured as infra) |
| Per-channel queue buffer | AWS SQS (prod) / local Solid Queue-backed queue (dev) |
| Channel-specific parsing | Channel containers (Roda) |
| Common ingestion contract | `/internal/ingest` endpoint in Rails |
| Users, teams, RBAC | Rails app |
| Contacts, channels, conversations, messages | Rails app + Postgres |
| Flow Engine | Rails services (inline) |
| Outbound queue + retries | Solid Queue |
| Real-time to dashboard | Solid Cable + Turbo Streams |
| Cache | Solid Cache |
| Authentication | Rails 8 built-in sessions |
| Automation rules | Rails (event-driven, Solid Queue jobs) |
| Audit log | `events` table in Rails |
| Attachment storage | Active Storage (S3 in prod, local disk in dev) |
| Agent workspace UI | Hotwire views in the same Rails app |

---

## Workspace — the agent's view

**Workspace is a UI concept, not a database entity.** No `workspaces` table exists. When an agent logs in, the dashboard composes their workspace dynamically:

```
User → belongs to Teams → Teams attend Channels → Channels receive Conversations
```

The workspace view is: "the conversations on channels attended by teams the logged-in user belongs to". Admins see everything in their account; agents see only what their teams cover.

### Sub-views within the workspace

The dashboard offers filtered lenses over the same underlying set of conversations. These are URL query parameters, not separate data structures:

| Sub-view | Filter |
|---|---|
| **Mine** | `conversations.assignee_id = current_user.id` |
| **Unassigned** | `conversations.assignee_id IS NULL AND conversations.status = 'queued'` |
| **My team** | `conversations.team_id IN (current_user.teams.pluck(:id))` |
| **By channel** | `conversations.channel_id = ?` — the agent picks from the list of channels their teams attend |
| **All** (admin only) | everything in `current_user.account` |

Each sub-view reuses the same conversation list component and the same real-time wiring. Switching between sub-views is a Turbo Frame navigation — the URL changes, the list re-renders, the WebSocket subscription narrows. No page reload.

### Real-time scoping

Solid Cable broadcasts conversation events per Channel. When an agent loads the workspace, the page subscribes to the set of Channels their teams attend. Messages arriving on a Channel the user has no access to are never sent to their browser — done via Turbo Stream signed stream names and a Pundit-style policy check in the `ConversationChannel`.

### Why this model

Treating "workspace" as a query composed at request time instead of as persistent state has three benefits:

1. **Team membership changes propagate instantly.** Add a user to a team → they see those channels on next page load. No migration, no backfill.
2. **No cross-cutting data integrity problems.** If a Channel is deactivated, no "ghost workspace" left behind. The view just returns fewer rows.
3. **Permission model is one rule, not a feature.** "Can I see this conversation?" answers every UI visibility question. Used by controllers, Solid Cable channels, and any future API.

---

## Audit — every action is an event

**Audit is not a feature. It is a principle.** Every action that changes the state of a Conversation, Contact, Channel, User, Team, Flow, or AutomationRule emits an `Event`. This is non-negotiable — it is the definition of how state changes in the system.

### The rule

State mutations happen exclusively in **Service objects** (`app/services/**/*.rb`). A service call either succeeds and emits one or more events, or it fails and emits nothing. Controllers, background jobs, and views **never** update records directly — they invoke services. Models may validate and persist, but they do not orchestrate.

The end of every service method looks like this:

```ruby
class Assignments::Transfer
  def call(conversation:, to_team:, to_user:, note:, actor:)
    # ...authorize, validate, update...

    Events.emit(
      name: "conversations:transferred",
      actor: actor,
      subject: conversation,
      payload: {
        from_team_id: previous_team_id,
        to_team_id: to_team&.id,
        from_user_id: previous_user_id,
        to_user_id: to_user&.id,
        note: note
      }
    )
  end
end
```

### The full event catalogue

Every event below is emitted somewhere. If a code path changes state without emitting one of these (or a new one added here), it is a bug.

```
accounts:*           created · updated
users:*              created · invited · activated · deactivated
                     signed_in · signed_out · role_changed
                     availability_changed
teams:*              created · updated · deleted
team_members:*       added · removed
channels:*           registered · updated · activated · deactivated · deleted
channel_teams:*      added · removed
contacts:*           created · updated · merged · deleted
contact_channels:*   created · deleted
conversations:*      created · status_changed · assigned · unassigned
                     transferred · resolved · reopened
messages:*           inbound · outbound · delivered · read · failed
flows:*              created · updated · activated · deactivated · deleted
                     started · advanced · handoff · completed · abandoned
automation_rules:*   created · updated · deleted · applied
```

Adding a new capability to the system means adding a new event name here before writing the service. Naming the event is the first design step.

### Timeline visibility on conversations

Every event whose `subject_type` is `Conversation` appears in the agent's timeline view of that conversation, interleaved with messages. An agent viewing a conversation sees:

- Messages (inbound/outbound, with status updates)
- System events: `created`, `transferred`, `assigned`, `resolved`, `reopened`, `handoff`
- Flow events: `started`, `advanced`, `completed`

Non-conversation events (`users:signed_in`, `teams:updated`, etc) do not appear in this timeline — they are only queryable via the Events table and, in the future, an admin Audit Log UI.

### Why this lives in Services

Three reasons the rule is strict:

1. **One truth about what happened.** If events could be emitted from anywhere, you can never trust the event log. Centralizing in Services makes it architecturally impossible to change state without recording it.
2. **Testability.** Services are the unit of test. Testing a service verifies "given this input, the state changes to X and these events are emitted." Nothing to mock.
3. **Future compatibility.** External webhooks, MCP tools, public API — all of these consume events. If events are reliable, every integration becomes trivial.

---

## Conversation Transfer

Since a Team can attend multiple Channels and a Channel is attended by multiple Teams, conversations often need to move between teams or between agents mid-conversation. Transfer is a first-class operation.

### Types of transfer

| Type | Meaning | Example |
|---|---|---|
| **Reassign** | User → User (same team) | João passes to Pedro before going on vacation |
| **Team transfer** | Team A → Team B | Support escalates to Finance |
| **Unassign** | Remove assignee, return to queue | Agent can't handle, puts back in the channel's queue |

All three are implemented by the same service (`Assignments::Transfer`) with different arguments. All three emit `conversations:transferred`.

### Permission rules

| Actor role | Can transfer |
|---|---|
| **Agent** | Conversations assigned to them |
| **Supervisor** | Any conversation on channels attended by any of their teams |
| **Admin** | Anything in their account |

Enforced in the service via a policy object (`ConversationPolicy#transferable_by?`). Rejected transfers do not emit events — they raise an authorization error.

### Target validation

The service verifies that the target Team (or target User's Teams) has access to the conversation's Channel via `channel_teams`. Transferring to a team that doesn't attend the channel is a 422, not a silent failure.

### Optional note

The transfer form in the dashboard has a free-text note field. If the agent fills it in, the note:

1. Is stored in the `Event.payload` under `note`
2. Creates a **system Message** in the conversation with `sender_type: "System"` and `content_type: "text"`, so the receiving agent sees context inline with the thread

If the note is empty, only the Event is recorded — no system message is created. This keeps threads clean when transfers are routine.

### Flow

```
1. Agent opens conversation → clicks "Transfer"
2. Dashboard shows form: Team (dropdown, filtered to channel's teams),
                        User (optional, dropdown filtered to team's members),
                        Note (optional textarea)
3. POST /conversations/:id/transfer → Assignments::Transfer.call
4. Service:
   · authorizes actor via ConversationPolicy
   · validates target team attends the channel
   · captures previous (from_team_id, from_user_id)
   · updates conversation.team_id and conversation.assignee_id
   · if note present: creates System Message via Messages::Create
   · emits conversations:transferred Event
5. Turbo Stream broadcasts:
   · to previous assignee (if any): conversation removed from "Mine"
   · to new assignee (if any): conversation appears in "Mine"
   · to the conversation's timeline: transfer entry appears
   · to workspace lists of all users whose teams changed visibility
```

### What transfer does NOT do

- **No approval workflow.** The spec might grow one, but v1 is "if you have permission, it's done, and it's logged." Supervisors review via audit log if needed.
- **No transfer-back button.** A transferred-back conversation is just another transfer. Simpler model.
- **No cross-account transfer.** Conversations never leave their account. Hard boundary.

---

## Infrastructure

### Postgres — single instance, single schema

One database, `falecom`, with all tables in `public`. No schema split needed anymore.

Solid Queue, Solid Cable, and Solid Cache live in the same Postgres instance (Rails 8 configures this by default with separate connection pools).

### Monorepo structure

```
falecom/
├── packages/
│   ├── falecom_channel/              ← internal gem: SQS consumer, Payload schema,
│   │   ├── lib/                        IngestClient, SendServer, logging.
│   │   │   └── falecom_channel/        Consumed by every container via path.
│   │   ├── falecom_channel.gemspec
│   │   └── spec/
│   │
│   ├── channels/                     ← one Roda app per channel type
│   │   ├── whatsapp-cloud/
│   │   │   ├── app.rb                ← ~100 lines: signature + parse + send
│   │   │   ├── config.ru
│   │   │   ├── lib/parser.rb
│   │   │   ├── lib/signature_verifier.rb
│   │   │   ├── lib/sender.rb
│   │   │   ├── Gemfile               ← gem "falecom_channel", path: "../../falecom_channel"
│   │   │   └── spec/
│   │   ├── zapi/
│   │   ├── evolution/
│   │   ├── instagram/
│   │   └── telegram/
│   │
│   └── app/                          ← Rails 8.1 — domain + API + dashboard
│       ├── app/
│       │   ├── components/           ← ViewComponent (JR Components copied in)
│       │   │   ├── ui/               ← JR base components: button, card, modal, etc.
│       │   │   ├── form_builders/    ← JR form builder components
│       │   │   └── app/              ← FaleCom-specific composite components
│       │   ├── controllers/
│       │   │   ├── internal/
│       │   │   │   └── ingest_controller.rb
│       │   │   ├── dashboard/
│       │   │   │   ├── conversations_controller.rb
│       │   │   │   ├── channels_controller.rb
│       │   │   │   └── ...
│       │   │   └── api/v1/           ← future public API
│       │   ├── models/
│       │   ├── services/
│       │   │   ├── ingestion/
│       │   │   ├── contacts/
│       │   │   ├── conversations/
│       │   │   ├── messages/
│       │   │   ├── flows/
│       │   │   ├── dispatch/
│       │   │   └── assignment/
│       │   ├── jobs/
│       │   │   ├── send_message_job.rb
│       │   │   ├── apply_automation_rules_job.rb
│       │   │   └── auto_resolve_stale_conversations_job.rb
│       │   ├── channels/             ← ActionCable channels (Solid Cable)
│       │   └── views/                ← Hotwire views
│       ├── db/
│       │   ├── migrate/
│       │   ├── queue_schema.rb       ← Solid Queue
│       │   ├── cable_schema.rb       ← Solid Cable
│       │   └── cache_schema.rb       ← Solid Cache
│       ├── app/frontend/             ← Vite entry points (JS, CSS, Stimulus controllers)
│       │   ├── entrypoints/
│       │   │   └── application.js
│       │   ├── controllers/          ← Stimulus controllers (JR ships some)
│       │   └── stylesheets/
│       │       └── application.css   ← Tailwind 4 imports + JR theme tokens
│       ├── config/
│       │   ├── queue.yml             ← Solid Queue worker config
│       │   ├── cable.yml             ← Solid Cable config
│       │   ├── recurring.yml         ← Solid Queue recurring jobs
│       │   └── vite.json             ← Vite config
│       └── Gemfile
│
├── .devcontainer/
│   ├── devcontainer.json              ← VS Code / Cursor workspace definition
│   └── workspace.Dockerfile           ← Ruby + tooling image for the dev workspace
│
├── infra/
│   ├── docker-compose.yml             ← dev runtime (workspace + Postgres + app + containers)
│   ├── docker-compose.prod.yml        ← reference only, not the deploy manifest
│   ├── dev-webhook/                   ← local API Gateway mock
│   └── terraform/                     ← production infra: API Gateway + SQS + DLQs + IAM
│
├── docs/
│   ├── specs/
│   └── plans/
│
├── CLAUDE.md
├── AGENTS.md
├── GLOSSARY.md
└── README.md
```

### Local development

Two complementary layers. They are not alternatives — you use both.

**`.devcontainer/`** — the **workspace environment** for a human developer. Defines what Ruby version is installed, what VS Code / Cursor / JetBrains extensions and settings are available, what CLI tools are pre-installed (node for Vite, aws-cli for Terraform, postgresql-client for psql), and what commands run on container creation (bundle install, npm install, db:prepare). Rails 8 ships with a `--devcontainer` generator that produces a sensible baseline we extend.

**`infra/docker-compose.yml`** — the **runtime services** the app depends on when running. Postgres, the Rails app, channel containers, dev-webhook, Solid Queue worker. Started inside (or referenced by) the devcontainer via `dockerComposeFile` + `service` in `devcontainer.json`, so opening the repo boots everything with one click.

Conceptually: the devcontainer is the IDE, the compose file is the stack. The devcontainer attaches you into a dedicated `workspace` service that has all your tools and mounts your code, and that service is part of the same compose network as Postgres, Rails, and the channel containers — so networking just works (`http://app:3000`, `postgres:5432`).

#### `.devcontainer/devcontainer.json`

```jsonc
{
  "name": "FaleCom",
  "dockerComposeFile": "../infra/docker-compose.yml",
  "service": "workspace",
  "workspaceFolder": "/workspaces/falecom",

  "features": {
    "ghcr.io/devcontainers/features/node:1": { "version": "lts" },
    "ghcr.io/devcontainers/features/aws-cli:1": {},
    "ghcr.io/devcontainers/features/github-cli:1": {},
    "ghcr.io/devcontainers/features/terraform:1": {}
  },

  "customizations": {
    "vscode": {
      "extensions": [
        "Shopify.ruby-lsp",
        "castwide.solargraph",
        "bradlc.vscode-tailwindcss",
        "esbenp.prettier-vscode",
        "hashicorp.terraform"
      ],
      "settings": {
        "rubyLsp.formatter": "standard",
        "editor.formatOnSave": true
      }
    }
  },

  "postCreateCommand": "bin/setup",
  "forwardPorts": [3000, 4000, 5432, 9292],
  "remoteUser": "vscode"
}
```

#### `infra/docker-compose.yml`

```yaml
services:
  # The developer's workspace. Devcontainer attaches here.
  # In production this service does not exist.
  workspace:
    build: ./workspace          # Dockerfile installs Ruby, standardrb, etc.
    volumes:
      - ..:/workspaces/falecom:cached
      - bundle_cache:/usr/local/bundle
    command: sleep infinity
    depends_on:
      - postgres

  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: falecom
      POSTGRES_PASSWORD: falecom
      POSTGRES_DB: falecom_development
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"

  # Dev-only webhook receiver that mimics AWS API Gateway.
  # In production this service does not exist.
  dev-webhook:
    build: ../infra/dev-webhook
    ports:
      - "4000:4000"
    environment:
      QUEUE_BACKEND: local
      DATABASE_URL: postgres://falecom:falecom@postgres:5432/falecom_development

  app:
    build: ../packages/app
    ports:
      - "3000:3000"
    environment:
      DATABASE_URL: postgres://falecom:falecom@postgres:5432/falecom_development
      FALECOM_INGEST_HMAC_SECRET: dev-ingest-secret
      FALECOM_DISPATCH_HMAC_SECRET: dev-dispatch-secret
      CHANNEL_WHATSAPP_CLOUD_URL: http://channel-whatsapp-cloud:9292
      CHANNEL_ZAPI_URL: http://channel-zapi:9292
    depends_on:
      - postgres

  app-jobs:
    build: ../packages/app
    command: bin/jobs
    environment:
      DATABASE_URL: postgres://falecom:falecom@postgres:5432/falecom_development
    depends_on:
      - postgres

  channel-whatsapp-cloud:
    build: ../packages/channels/whatsapp-cloud
    environment:
      QUEUE_BACKEND: local              # local | sqs
      DATABASE_URL: postgres://falecom:falecom@postgres:5432/falecom_development
      FALECOM_API_URL: http://app:3000
      FALECOM_INGEST_HMAC_SECRET: dev-ingest-secret
      FALECOM_DISPATCH_HMAC_SECRET: dev-dispatch-secret
      WHATSAPP_ACCESS_TOKEN: ${WHATSAPP_ACCESS_TOKEN:-dev-placeholder}
    depends_on:
      - postgres

  channel-zapi:
    build: ../packages/channels/zapi
    environment:
      QUEUE_BACKEND: local
      DATABASE_URL: postgres://falecom:falecom@postgres:5432/falecom_development
      FALECOM_API_URL: http://app:3000
      FALECOM_INGEST_HMAC_SECRET: dev-ingest-secret
      FALECOM_DISPATCH_HMAC_SECRET: dev-dispatch-secret
    depends_on:
      - postgres

volumes:
  postgres_data:
  bundle_cache:
```

#### Production vs development compose

The compose above is **for development**. Production deployments do **not** use docker-compose — they use real infrastructure: AWS API Gateway (not `dev-webhook`), SQS (not a local queue table), RDS or similar (not the `postgres` container), and each service runs as its own deploy unit (ECS task, Fly machine, Kamal-managed VM, whatever the deploy target is).

There is a `infra/docker-compose.prod.yml` **only** for reference — showing how the services relate — but it is not the production deployment manifest. That lives in `infra/terraform/` (AWS Gateway, SQS, RDS, IAM) plus per-service deploy configs.

#### Dev workflow

Opening the repo in VS Code / Cursor with the devcontainer extension triggers:

1. Docker Compose pulls images and builds the workspace.
2. The workspace container is created with Ruby + tooling.
3. `postCreateCommand: bin/setup` runs — `bundle install`, `yarn install`, `bin/rails db:prepare`, seeds dev channels.
4. The editor attaches into the workspace container. Files open, extensions work, terminal sessions are inside the container.
5. From the integrated terminal: `bin/dev` starts Rails + Vite; separately `docker compose up channel-whatsapp-cloud channel-zapi dev-webhook` for the ingestion pipeline.

#### Without a devcontainer

Devcontainer is the supported path. For contributors without devcontainer support, `bin/setup` + `docker compose up` works from the host, given the right Ruby version installed locally via `mise` or `asdf`.


### Queue Adapter (inside `falecom_channel` gem)

Part of the shared gem. Used by channel containers to pull messages, and by the `dev-webhook` helper to enqueue. In production, AWS API Gateway writes directly to SQS, so nothing "enqueues" in our own code — only consumers run.

```ruby
module FaleComChannel
  class QueueAdapter
    def self.build(backend:, queue_name:)
      case backend
      when "sqs"   then SqsAdapter.new(queue_name)
      when "local" then LocalAdapter.new(queue_name)
      end
    end

    def enqueue(payload); end
    def consume(&handler); end
    def ack(message_id); end
    def nack(message_id); end
  end
end
```

The `local` adapter uses Postgres (via a simple `inbound_queue` table) for dev, so you don't need any infra beyond Postgres. SQS for prod.

---


## FaleCom DB Schema

The tables below describe the **logical schema** — the target state the database should reach. Every table, column, and index is created through Rails migrations (`bin/rails generate migration`, edit the generated file, `bin/rails db:migrate`). Never write raw SQL files that bypass ActiveRecord migrations.

Solid Queue, Solid Cable, and Solid Cache install their own tables via Rails 8 generators (`bin/rails solid_queue:install`, etc.). Not shown here. The Rails 8 authentication generator creates a `sessions` table and `users` table skeleton — we extend `users` with the columns below.

### ActiveRecord conventions used throughout

Before reading the schema, internalize these conventions. They affect how migrations and models are written:

1. **Primary keys** — every table has an implicit `id bigint PRIMARY KEY` generated by Rails. Not shown in the tables below.
2. **Timestamps** — `t.timestamps` in migrations produces `created_at` and `updated_at`, both `NOT NULL`. Shown as the single line "timestamps" in the tables below.
3. **Reserved column names** — `type` is reserved by ActiveRecord for STI. Columns that represent a kind/category use a specific name (`channel_type`, `node_type`, `message_type`) instead of plain `type`. Violations require `self.inheritance_column = nil` in the model, which we avoid.
4. **Enums** — string-backed enums via `enum :status, %w[bot queued assigned resolved], validate: true`. Database column is `text NOT NULL` with a check constraint enforcing allowed values. Integer-backed enums are forbidden — they break when values are added or reordered.
5. **JSONB defaults** — migrations use `default: {}` (Hash) or `default: []` (Array). The database column is `jsonb NOT NULL DEFAULT '{}'`.
6. **Foreign keys** — always `foreign_key: true` in migrations. Always named `<singular>_id`. Indexes are implicit with `references`.
7. **Encrypted attributes** — `encrypts :access_token` in the model, no schema change needed. Used for sensitive fields in `channels.credentials`.
8. **Partial unique indexes** — created via `add_index :table, [:col], unique: true, where: "col IS NOT NULL"`.
9. **Check constraints** — `t.check_constraint "status IN ('bot','queued','assigned','resolved')"` to enforce enum values at the DB level too. Defense in depth.

### Accounts — tenant boundary

| Column | Type | Notes |
|---|---|---|
| name | string, null: false | |
| locale | string, default: 'pt-BR' | |
| auto_resolve_duration | integer, default: 7 | days of inactivity before auto-resolve |
| timestamps | | |

### Users — agents, admins

Rails 8 auth generator creates this table. We add columns to it.

| Column | Type | Notes |
|---|---|---|
| account_id | references | NOT NULL, FK |
| name | string, null: false | |
| email | string, null: false, unique | |
| password_digest | string, null: false | from auth generator |
| role | string, null: false | enum: `admin`, `supervisor`, `agent` |
| availability | string, default: 'offline' | enum: `online`, `busy`, `offline` |
| timestamps | | |

### Teams

| Column | Type | Notes |
|---|---|---|
| account_id | references | NOT NULL, FK |
| name | string, null: false | |
| timestamps | | |

### TeamMembers — join (Team ↔ User)

| Column | Type | Notes |
|---|---|---|
| team_id | references | NOT NULL, FK, indexed |
| user_id | references | NOT NULL, FK, indexed |
| timestamps | | |

Unique index on `(team_id, user_id)`.

### Channels — registered provider instances

The registry the API checks on every ingest. A Channel is one specific configured provider account — e.g., "WhatsApp Vendas 5511999999999", "Instagram @loja_promo". Two phone numbers on WhatsApp Cloud are two different Channels, both with `channel_type: whatsapp_cloud`. All channel-level behavior (flow, auto-assign, greeting) lives here.

| Column | Type | Notes |
|---|---|---|
| account_id | references | NOT NULL, FK |
| channel_type | string, null: false | enum: `whatsapp_cloud`, `zapi`, `evolution`, `instagram`, `telegram` |
| identifier | string, null: false | phone number, page ID, bot username — unique per `channel_type` |
| name | string, null: false | human-readable ("WhatsApp Vendas", "Instagram @loja_promo") |
| active | boolean, null: false, default: true | |
| config | jsonb, null: false, default: {} | non-sensitive provider settings |
| credentials | jsonb, null: false, default: {} | sensitive — `encrypts :credentials` in model |
| active_flow_id | bigint | nullable FK to `flows.id`. Added in a later migration to avoid a circular reference. 1:1 in v1 |
| auto_assign | boolean, null: false, default: false | |
| auto_assign_config | jsonb, null: false, default: {} | `round_robin`, `team_id`, `capacity` |
| greeting_enabled | boolean, null: false, default: false | |
| greeting_message | text | |
| lock_to_single_conversation | boolean, null: false, default: false | |
| timestamps | | |

Unique index on `(channel_type, identifier)`. Index on `(account_id, active)`.

### ChannelTeams — join (Channel ↔ Team)

A Channel is attended by one or more Teams. A Team attends one or more Channels. The assignment of a specific User to a Channel is indirect: User belongs to Team, Team attends Channel.

| Column | Type | Notes |
|---|---|---|
| channel_id | references | NOT NULL, FK |
| team_id | references | NOT NULL, FK |
| timestamps | | |

Unique index on `(channel_id, team_id)`.

### Contacts

| Column | Type | Notes |
|---|---|---|
| account_id | references | NOT NULL, FK |
| name | string | |
| email | string | |
| phone_number | string | |
| identifier | string | user-defined external ID |
| additional_attributes | jsonb, null: false, default: {} | |
| timestamps | | |

### ContactChannels — how a contact appears on a specific channel

| Column | Type | Notes |
|---|---|---|
| contact_id | references | NOT NULL, FK |
| channel_id | references | NOT NULL, FK |
| source_id | string, null: false | provider-scoped unique ID (WhatsApp number, Instagram PSID) |
| timestamps | | |

Unique index on `(channel_id, source_id)`.

### Conversations

| Column | Type | Notes |
|---|---|---|
| account_id | references | NOT NULL, FK |
| channel_id | references | NOT NULL, FK |
| contact_id | references | NOT NULL, FK |
| contact_channel_id | references | NOT NULL, FK |
| status | string, null: false, default: 'bot' | enum: `bot`, `queued`, `assigned`, `resolved` |
| assignee_id | references | nullable, FK to users |
| team_id | references | nullable, FK |
| display_id | integer, null: false | per-account display number |
| last_activity_at | datetime | |
| additional_attributes | jsonb, null: false, default: {} | |
| timestamps | | |

Indexes:
- `(account_id, status, last_activity_at DESC)`
- `(channel_id, status)`
- `(assignee_id, status)`
- `(team_id, status)`
- Unique `(account_id, display_id)` — display_id is per-account

### Messages

| Column | Type | Notes |
|---|---|---|
| account_id | references | NOT NULL, FK |
| conversation_id | references | NOT NULL, FK |
| channel_id | references | NOT NULL, FK |
| direction | string, null: false | enum: `inbound`, `outbound` |
| content | text | |
| content_type | string, null: false, default: 'text' | enum: `text`, `image`, `audio`, `video`, `document`, `location`, `contact_card`, `input_select`, `button_reply`, `template` |
| status | string, null: false, default: 'received' | enum: `received`, `pending`, `sent`, `delivered`, `read`, `failed` |
| external_id | string | provider message ID |
| sender_type | string | polymorphic: `User`, `Contact`, `System`, `Bot` |
| sender_id | bigint | polymorphic |
| reply_to_external_id | string | |
| error | text | |
| metadata | jsonb, null: false, default: {} | provider-specific extras from Common Ingestion Payload |
| raw | jsonb | original provider payload, audit only |
| sent_at | datetime | |
| timestamps | | |

Indexes:
- `(conversation_id, created_at)`
- Partial unique `(channel_id, external_id) WHERE external_id IS NOT NULL` — idempotency
- `(sender_type, sender_id)` — polymorphic lookup

### Attachments

Handled via Active Storage (`has_many_attached :files`). No explicit table in our schema — Active Storage migrations create `active_storage_blobs` and `active_storage_attachments`.

### Flows

| Column | Type | Notes |
|---|---|---|
| account_id | references | NOT NULL, FK |
| name | string, null: false | |
| description | text | |
| is_active | boolean, null: false, default: true | |
| inactivity_threshold_hours | integer, null: false, default: 24 | |
| root_node_id | bigint | nullable FK to `flow_nodes.id`, set after the root node is created |
| timestamps | | |

### FlowNodes

Note: column is `node_type`, not `type`, to avoid STI activation.

| Column | Type | Notes |
|---|---|---|
| flow_id | references | NOT NULL, FK |
| node_type | string, null: false | enum: `message`, `menu`, `collect`, `handoff`, `branch` |
| content | jsonb, null: false | |
| next_node_id | references | nullable, self-FK to flow_nodes |
| timestamps | | |

### ConversationFlows — runtime state of a flow execution

| Column | Type | Notes |
|---|---|---|
| conversation_id | references | NOT NULL, FK |
| flow_id | references | NOT NULL, FK |
| current_node_id | references | nullable, FK to flow_nodes |
| state | jsonb, null: false, default: {} | |
| status | string, null: false, default: 'active' | enum: `active`, `completed`, `abandoned` |
| started_at | datetime, null: false, default: -> { 'CURRENT_TIMESTAMP' } | |
| last_interaction_at | datetime | |
| timestamps | | |

Unique index on `(conversation_id)` — one active flow per conversation.

### AutomationRules

| Column | Type | Notes |
|---|---|---|
| account_id | references | NOT NULL, FK |
| event_name | string, null: false | e.g., `messages:inbound`, `conversations:created` |
| conditions | jsonb, null: false, default: [] | |
| actions | jsonb, null: false, default: [] | |
| active | boolean, null: false, default: true | |
| timestamps | | |

Index on `(account_id, event_name, active)`.

### Events — audit log

Every state-changing action in the system emits an Event. This table is append-only — no updates, no deletes. It is the authoritative record of what happened, by whom, to what, and when.

| Column | Type | Notes |
|---|---|---|
| account_id | references | nullable (system events) |
| name | string, null: false | module-prefixed event name, e.g. `conversations:transferred` |
| actor_type | string | polymorphic: `User`, `Contact`, `System`, `Bot` |
| actor_id | bigint | polymorphic — nullable for `System` events |
| subject_type | string, null: false | the entity whose state changed: `Conversation`, `Contact`, `Channel`, `User`, `Team` |
| subject_id | bigint, null: false | |
| payload | jsonb, null: false, default: {} | event-specific details (from_team_id, to_team_id, note, etc) |
| created_at | datetime, null: false | no `updated_at` — events are immutable |

Indexes:
- `(account_id, name, created_at DESC)` — "all transfers today across the account"
- `(subject_type, subject_id, created_at DESC)` — "full history of conversation 123"
- `(actor_type, actor_id, created_at DESC)` — "everything João did this week"
- `(account_id, created_at DESC)` — general audit feed

### Migration strategy

Migrations are ordered so foreign keys reference existing tables. The suggested order for the initial bulk migration set:

1. `accounts`
2. `users`, `sessions`, `teams`, `team_members`
3. `channels` (without `active_flow_id` FK yet)
4. `channel_teams`
5. `flows` (without `root_node_id` FK yet)
6. `flow_nodes`
7. Add `flows.root_node_id` FK (separate migration — avoids circular dependency with `flow_nodes`)
8. Add `channels.active_flow_id` FK (separate migration — avoids circular dependency with `flows`)
9. `contacts`, `contact_channels`
10. `conversations`
11. `messages`
12. `conversation_flows`
13. `automation_rules`
14. `events`
15. Active Storage install
16. Solid Queue / Solid Cable / Solid Cache installs

Each migration is reversible. Data backfills, when needed, run as separate migrations or rake tasks triggering Solid Queue jobs — not inline in schema migrations.

---

## Security

### `/internal/ingest` authentication

Every POST from channel containers includes:

```
X-FaleCom-Signature: sha256=<HMAC-SHA256 of raw body, using FALECOM_INGEST_HMAC_SECRET>
X-FaleCom-Timestamp: <unix timestamp>
```

Rails verifies:
- Signature matches
- Timestamp is within 5 minutes (replay protection)

Only channel containers share this secret. AWS API Gateway does not validate it — it only moves raw bytes to SQS.

### Channel container `/send` authentication

Rails POSTs to channel containers using the same HMAC scheme, with a different secret (`FALECOM_DISPATCH_HMAC_SECRET`). Channel containers verify.

### Channel signatures (provider → us)

Each provider has its own signature scheme (Meta uses `X-Hub-Signature-256`, Z-API uses a token query param, etc.). **Channel containers validate these after pulling from SQS**, on the raw payload (which is preserved byte-for-byte by API Gateway → SQS integration). Invalid signature → container NACKs the message (goes to DLQ after max retries). This design choice has a trade-off: API Gateway returns 200 before signature is validated, so a flood of bogus signed payloads could cost SQS operations — but DLQ + CloudWatch alarms catch this, and the trade gives us one universal "Layer 1" with no code we have to maintain. If a specific provider becomes a target of abuse, we can add a signature-validating Lambda authorizer on that route without changing anything downstream.

### AWS API Gateway posture

API Gateway is configured with:
- Direct SQS integration (no Lambda) per channel route
- Throttling limits per route (per-second + burst) sized to each provider's legitimate peak
- Request body size limits matching each provider's documented max
- CloudWatch alarms on 4xx/5xx rates and DLQ depth

### Multi-tenancy isolation

Every controller action scopes by `current_user.account_id`. Models have `default_scope` disabled (it causes pain) but every service uses `account.conversations.find(...)` rather than `Conversation.find(...)`. Enforced in code review.

---

## Build Order

### Phase 1 — Foundation

1. Monorepo scaffold, Ruby tooling, `.ruby-version`, root `Gemfile` for shared dev gems, `standardrb`
2. `CLAUDE.md` at root with full dev flow (DEFINE → PLAN → BUILD → VERIFY → DOCS → REVIEW → SHIP)
3. `AGENTS.md` per package referencing root `CLAUDE.md`
4. `GLOSSARY.md` extracted from this document
5. CI pipeline — GitHub Actions: `standardrb` + tests on every PR
6. `.devcontainer/devcontainer.json` + `workspace.Dockerfile` — developer workspace image with Ruby, standardrb, node, aws-cli, terraform, postgresql-client. Extensions (Ruby LSP, Tailwind, Terraform) auto-installed on open
7. `infra/docker-compose.yml` with workspace + Postgres + placeholders for app and channel containers (services added as packages come online)
8. Rails 8.1 app scaffold (`rails new packages/app --database=postgresql --devcontainer --skip-asset-pipeline --skip-javascript`). The `--devcontainer` flag generates a Rails-aware starting point we then merge into the monorepo-level `.devcontainer/`
9. Solid Queue, Solid Cable, Solid Cache installed and configured
10. Rails 8 auth generator (`bin/rails generate authentication`)
11. `vite_rails` installed and configured (`bundle add vite_rails && bundle exec vite install`)
12. TailwindCSS 4 installed via Vite (per JR Components getting started guide)
13. `view_component` gem installed (`bundle add view_component`)
14. JR Components copied into `app/components/ui/` following the Jetrockets getting-started guide. Components are owned in the repo, not a gem dependency
15. JR form builder configured as the app's default form builder
16. Base layout with JR Navbar + Sidebar, login page using JR form fields, dashboard shell
17. `bin/setup` script — idempotent, safe to re-run. Runs `bundle install`, `yarn install`, `rails db:prepare`, seeds dev account + dev channels. Called by `postCreateCommand` in devcontainer and by contributors not using devcontainer

### Phase 2 — Core domain

1. Migrations, generated and applied in the order documented in `## FaleCom DB Schema → Migration strategy`. Each migration is reversible. Every column that should be `NOT NULL` is marked as such. Enum columns get check constraints in addition to model-level `enum`.
2. ActiveRecord models with:
   - `belongs_to` / `has_many` associations
   - `enum` declarations matching the migrations' check constraints
   - `validates` for required fields
   - `encrypts :credentials` on `Channel`
   - `self.inheritance_column = nil` only if a model truly needs a `type` column — we expect zero such cases, since the schema avoids it
   - Account scoping helpers (`belongs_to :account`, `default_scope -> { where(account: Current.account) }` is **forbidden** — scoping is explicit in every query)
3. `db/seeds.rb` creates one dev Account, an admin User, sample Teams ("Vendas", "Suporte"), two Channels (one WhatsApp Cloud, one Z-API), and `ChannelTeam` associations wiring both Teams to both Channels
4. Dashboard views (Hotwire): conversation list, conversation detail with message thread, reply form. Built with ViewComponent + JR components
5. Real-time: Turbo Streams broadcast on `Message` create, subscribe in dashboard views
6. User availability toggle, basic team management pages

### Phase 3 — Ingestion pipeline

1. `packages/falecom_channel` gem: Consumer, Payload, IngestClient, SendServer, Logging. Covered by its own RSpec suite (including a fake SQS adapter for the Consumer tests). Published only via path.
2. Channel registration: admin UI to create/edit `Channel` records (channel_type, identifier, name, active, credentials). At least WhatsApp Cloud and Z-API in seed data so we exercise two different provider shapes.
3. Rails `Internal::IngestController` with HMAC + timestamp verification and Channel registration lookup (rejects unknown `channel_type + identifier` with 422).
4. `Ingestion::ProcessMessage` service + `Contacts::Resolve`, `Conversations::ResolveOrCreate`, `Messages::Create`. Idempotency via `(channel_id, external_id)` unique index.
5. `QueueAdapter` (inside the gem): `local` (Postgres-backed table) and `sqs` implementations.
6. `packages/channels/whatsapp-cloud`: the reference container. Uses `falecom_channel`, adds `Parser`, `SignatureVerifier`, `Sender`. Should end up around 200–300 lines total across all files.
7. `infra/dev-webhook` — tiny Roda app that mimics AWS API Gateway locally: receives POST, routes by path to the right local queue. Dev-only.
8. `infra/terraform` — API Gateway (HTTP API) with one route per channel type, direct SQS integration, per-route throttling, DLQs, IAM. Not deployed yet in Phase 3 but reviewable.
9. End-to-end integration test: real webhook POST → `dev-webhook` → local queue → `whatsapp-cloud` container → `/internal/ingest` → DB → Turbo Stream broadcast visible in test client.

### Phase 4 — Outbound

1. Agent reply form in dashboard (Turbo Stream target).
2. `Dispatch::Outbound` service creates Message (status: `pending`), enqueues `SendMessageJob`.
3. `SendMessageJob` (Solid Queue) POSTs to channel container `/send` with HMAC.
4. `whatsapp-cloud` container `/send` endpoint: calls Meta Graph API, returns `external_id`.
5. Delivery status webhook flow: provider → AWS API Gateway → SQS → channel container → `/internal/ingest` (as `outbound_status_update`) → message status update + Turbo Stream broadcast. (Dev uses `dev-webhook` in place of API Gateway.)
6. Retry/failure handling: Solid Queue exponential backoff, dashboard shows failed state.

### Phase 5 — Assignment, Transfer, Teams

1. `ConversationPolicy` — Pundit-style policy object answering `can_view?`, `can_reply?`, `can_transfer?`, `can_resolve?`. Used by controllers and by the ConversationChannel for Solid Cable authorization.
2. `Assignments::AutoAssign` service (round-robin, capacity-based, team-scoped). Emits `conversations:assigned`.
3. Auto-assign rules configurable per channel.
4. Agent availability affects auto-assign eligibility.
5. `Assignments::Transfer` service — handles reassign (User→User), team transfer (Team→Team), unassign. Emits `conversations:transferred`. Optional note creates a system `Message` in the thread.
6. Transfer UI — button on conversation detail view, modal with Team dropdown (filtered to channel's teams), User dropdown (filtered to team members), optional note textarea.
7. Conversation timeline component — renders messages and conversation-scoped events (`created`, `assigned`, `transferred`, `resolved`, `reopened`, `handoff`) interleaved by `created_at`. Uses ViewComponent with a polymorphic renderer per event type.
8. Turbo Stream broadcasts for transfer — update sender's workspace ("Mine" loses the conversation), receiver's workspace ("Mine" gains it), and the conversation timeline (new transfer entry visible to both).

### Phase 6 — Flow Engine

1. Migrations for flows, flow_nodes, conversation_flows
2. Flow models + node types (message, menu, collect, handoff, branch)
3. `Flows::Advance`, `Flows::Start`, `Flows::Handoff` services
4. Simple Rails form-based flow editor (list nodes, add node, link nodes)
5. Flow activation/deactivation per channel
6. Inactivity threshold logic in `Flows::Start`
7. Integration tests covering full bot cycle + handoff

### Phase 7 — Additional channels

Each is a standalone Roda app following the `whatsapp-cloud` pattern. Scope per channel is small: parse provider webhook → common payload, and on outbound translate common payload → provider API.

1. `zapi`
2. `evolution`
3. `instagram`
4. `telegram`

---

## Dev Flow

Every change follows **DEFINE → PLAN → BUILD → VERIFY → DOCS → REVIEW → SHIP**, in order. The operational details — what each phase requires, what triggers a loop back, repository conventions, how to work when stuck — live in [`CLAUDE.md`](./CLAUDE.md) at the repo root. That file is the source of truth for anyone (human or agent) working in this codebase.

---

## Roadmap

- **Visual flow builder** — canvas-based drag-and-drop editor (React Flow, iframe/Stimulus bridge)
- **Audit log UI** — searchable event history
- **MCP module** — expose FaleCom as a tool for AI agents
- **Public API** (`/api/v1/*`) — for integrations and external dashboards
- **Multi-tenant admin** — account provisioning UI, billing
- **CLI** — manage flows, channels, users from terminal
- **Message templates** — WhatsApp template sync and approval flow
- **Reports & CSAT** — conversation metrics, agent performance, satisfaction surveys
- **SLA / response time tracking**
- **Knowledge base / canned responses**

---

## What We Are Not Building

- Our own WebSocket server — Solid Cable handles this
- Our own job system — Solid Queue handles this
- A separate frontend SPA — Rails + Hotwire is the UI layer
- A Kubernetes-native deployment story for v1 — Docker Compose is enough
- Multi-region / geo-distributed deployment for v1
- Our own authentication framework — Rails 8 generator is enough
- Our own background job DSL — ActiveJob on Solid Queue is enough

---

## References

### Rails 8
- Release notes: https://rubyonrails.org/2024/11/7/rails-8-no-paas-required
- Solid Queue: https://github.com/rails/solid_queue
- Solid Cable: https://github.com/rails/solid_cable
- Solid Cache: https://github.com/rails/solid_cache
- Authentication generator: https://guides.rubyonrails.org/security.html#authentication

### UI
- Hotwire: https://hotwired.dev/
- ViewComponent: https://viewcomponent.org/
- JR Components (Jetrockets): https://ui.jetrockets.com/ui
- JR Getting Started: https://ui.jetrockets.com/ui/getting_started
- TailwindCSS 4: https://tailwindcss.com/
- Vite Rails: https://vite-ruby.netlify.app/

### Web framework for tiny services
- Roda: https://roda.jeremyevans.net/

### AWS
- SQS: https://docs.aws.amazon.com/sqs/
- API Gateway HTTP API: https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api.html
- API Gateway → SQS integration: https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-develop-integrations-aws-services.html
- `aws-sdk-sqs` Ruby gem: https://github.com/aws/aws-sdk-ruby

### Dev environment
- Dev Containers spec: https://containers.dev/
- Rails 8 devcontainer generator: https://guides.rubyonrails.org/getting_started_with_devcontainer.html
- Docker Compose: https://docs.docker.com/compose/

### Channel providers (per-container documentation lives inside each container's README)
- WhatsApp Cloud API: https://developers.facebook.com/docs/whatsapp/cloud-api
- Z-API: https://developer.z-api.io/
- Evolution API: https://doc.evolution-api.com/
- Instagram Messaging: https://developers.facebook.com/docs/messenger-platform/instagram
- Telegram Bot API: https://core.telegram.org/bots/api

---

## Open Questions

- **Attachment handling latency** — for large media (video, audio), should the channel container download and forward as base64, or should it pass a temporary URL that Rails fetches asynchronously via Solid Queue? Leaning toward the latter to keep the ingest path fast.
- **Rate limiting per channel** — each provider has different rate limits. Should this live in the channel container (closer to the provider) or in Solid Queue job config (closer to the dispatch logic)? Probably both — container-level for bursts, job-level for sustained rate.
- **Outbound queue backpressure** — if a channel container is down, SendMessageJob retries via Solid Queue. But do we need a circuit breaker to pause dispatching when too many jobs are failing? Deferred until we have real traffic data.
