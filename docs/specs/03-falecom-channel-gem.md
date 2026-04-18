# Spec: `falecom_channel` Gem

> **Phase:** 3 (Ingestion pipeline) — gem only
> **Execution Order:** 3 of 7 — after Spec 1 *(can run in parallel with Spec 2)*
> **Date:** 2026-04-17
> **Status:** Draft — awaiting approval
> **Depends on:** [Spec 1: Monorepo Foundation](./01-monorepo-foundation.md) (monorepo layout exists)

---

## 1. What problem are we solving?

Every channel container (WhatsApp Cloud, Z-API, Evolution, Instagram, Telegram) performs the same four infrastructure jobs:

1. Pull messages from a queue (SQS in prod, Postgres in dev).
2. POST normalized payloads to Rails `/internal/ingest` with HMAC authentication.
3. Expose a `/send` endpoint for outbound dispatch, also HMAC-authenticated.
4. Log with structured JSON and correlation IDs.

Only the *translation* between provider format and the common payload is unique per channel. Without a shared gem, this infrastructure code would be duplicated across five containers.

The `falecom_channel` gem is the single shared surface between channel containers and the Rails app. It defines the Common Ingestion Payload schema — the most important contract in the system.

---

## 2. What is in scope?

### 2.1 Gem scaffold

- [ ] `packages/falecom_channel/` — standard Ruby gem layout.
- [ ] `falecom_channel.gemspec` with dependencies: `dry-struct`, `dry-validation`, `faraday`, `roda`, `aws-sdk-sqs`, `pg` (for local adapter).
- [ ] `Gemfile` referencing the gemspec.
- [ ] `lib/falecom_channel.rb` — top-level require.
- [ ] `spec/` directory with RSpec configured.
- [ ] Versioning: `FaleComChannel::VERSION = "0.1.0"`. Breaking changes to the payload bump major version.

### 2.2 `FaleComChannel::Payload`

The **single source of truth** for the Common Ingestion Payload contract. Uses `dry-struct` for structure and `dry-validation` for validation.

**Inbound message schema (`FaleComChannel::Payload::InboundMessage`):**

```ruby
attribute :type, Types::String.constrained(included_in: %w[inbound_message])
attribute :channel do
  attribute :type, Types::String
  attribute :identifier, Types::String
end
attribute :contact do
  attribute :source_id, Types::String
  attribute? :name, Types::String.optional
  attribute? :phone_number, Types::String.optional
  attribute? :email, Types::String.optional
  attribute? :avatar_url, Types::String.optional
end
attribute :message do
  attribute :external_id, Types::String
  attribute :direction, Types::String.constrained(included_in: %w[inbound outbound])
  attribute? :content, Types::String.optional
  attribute :content_type, Types::String.constrained(included_in: CONTENT_TYPES)
  attribute? :attachments, Types::Array.default([].freeze)
  attribute :sent_at, Types::String  # ISO 8601
  attribute? :reply_to_external_id, Types::String.optional
end
attribute? :metadata, Types::Hash.default({}.freeze)
attribute? :raw, Types::Hash.optional
```

**Outbound status update schema (`FaleComChannel::Payload::OutboundStatusUpdate`):**

```ruby
attribute :type, Types::String.constrained(included_in: %w[outbound_status_update])
attribute :channel do
  attribute :type, Types::String
  attribute :identifier, Types::String
end
attribute :external_id, Types::String
attribute :status, Types::String.constrained(included_in: %w[sent delivered read failed])
attribute :timestamp, Types::String  # ISO 8601
attribute? :error, Types::String.optional
attribute? :metadata, Types::Hash.default({}.freeze)
```

**Outbound dispatch schema (`FaleComChannel::Payload::OutboundMessage`):**

```ruby
attribute :type, Types::String.constrained(included_in: %w[outbound_message])
attribute :channel do
  attribute :type, Types::String
  attribute :identifier, Types::String
end
attribute :contact do
  attribute :source_id, Types::String
end
attribute :message do
  attribute :internal_id, Types::Integer
  attribute? :content, Types::String.optional
  attribute :content_type, Types::String
  attribute? :attachments, Types::Array.default([].freeze)
  attribute? :reply_to_external_id, Types::String.optional
end
attribute? :metadata, Types::Hash.default({}.freeze)
```

**Validation API:**

```ruby
FaleComChannel::Payload.validate!(hash)  # raises on invalid
FaleComChannel::Payload.valid?(hash)     # returns boolean
FaleComChannel::Payload.parse(hash)      # returns typed struct or raises
```

The `validate!` method determines the schema by the `type` field and applies the corresponding validation.

### 2.3 `FaleComChannel::QueueAdapter`

Abstract interface with two implementations:

**`FaleComChannel::QueueAdapter::SqsAdapter`:**
- Wraps `aws-sdk-sqs`.
- `consume(&handler)` — long-polls SQS, yields message body + headers.
- `ack(receipt_handle)` — deletes message from queue.
- `nack(receipt_handle)` — changes visibility timeout to 0 (immediate retry).
- Configurable: `queue_url`, `wait_time_seconds`, `visibility_timeout`.

**`FaleComChannel::QueueAdapter::LocalAdapter`:**
- Uses a Postgres table (`inbound_queue`) for dev.
- `enqueue(queue_name, payload)` — inserts a row.
- `consume(&handler)` — polls the table with `SELECT ... FOR UPDATE SKIP LOCKED`, yields rows.
- `ack(id)` — deletes the row.
- `nack(id)` — sets `retry_at` to now (immediate retry).
- The table schema:

```sql
CREATE TABLE inbound_queue (
  id bigserial PRIMARY KEY,
  queue_name text NOT NULL,
  payload jsonb NOT NULL,
  headers jsonb NOT NULL DEFAULT '{}',
  retry_at timestamp DEFAULT CURRENT_TIMESTAMP,
  created_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_inbound_queue_consume ON inbound_queue (queue_name, retry_at);
```

**Factory:**

```ruby
FaleComChannel::QueueAdapter.build(
  backend: ENV.fetch("QUEUE_BACKEND", "local"),  # "sqs" | "local"
  queue_name: ENV.fetch("SQS_QUEUE_NAME")
)
```

### 2.4 `FaleComChannel::Consumer`

A mixin module for channel container apps. Provides the polling loop.

```ruby
module FaleComChannel::Consumer
  def self.included(base)
    base.extend ClassMethods
  end

  module ClassMethods
    def queue_name(name); end
    def concurrency(n); end
  end

  def start
    # Builds queue adapter, starts N threads, each calling #handle per message
  end

  def handle(raw_body, headers)
    raise NotImplementedError
  end

  def ingest_client
    @ingest_client ||= FaleComChannel::IngestClient.new
  end
end
```

Key behaviors:
- Configurable concurrency (default 10).
- Graceful shutdown on SIGTERM/SIGINT — finishes in-flight messages before exiting.
- Failed `handle` calls → `nack` (message returns to queue / goes to DLQ after max retries).
- Successful `handle` calls → `ack`.

### 2.5 `FaleComChannel::IngestClient`

Faraday HTTP client for `POST /internal/ingest`.

```ruby
client = FaleComChannel::IngestClient.new(
  api_url: ENV.fetch("FALECOM_API_URL"),
  hmac_secret: ENV.fetch("FALECOM_INGEST_HMAC_SECRET")
)

client.post(payload_hash)
```

Behaviors:
- Sets `X-FaleCom-Signature: sha256=<HMAC-SHA256 of JSON body>`.
- Sets `X-FaleCom-Timestamp: <unix timestamp>`.
- Retries on 5xx responses (3 retries, exponential backoff).
- Raises `FaleComChannel::IngestError` on persistent failure.
- Timeouts: connect 5s, read 10s.
- Structured JSON logging with correlation ID.

### 2.6 `FaleComChannel::SendServer`

Roda base app for the `/send` endpoint.

```ruby
class FaleComChannel::SendServer < Roda
  plugin :json
  plugin :json_parser

  route do |r|
    r.post "send" do
      verify_hmac!(r)  # raises 401 on failure
      payload = FaleComChannel::Payload.parse(r.params)
      result = handle_send(payload)
      { external_id: result.external_id }
    end

    r.get "health" do
      { status: "ok" }
    end
  end

  def handle_send(payload)
    raise NotImplementedError, "Subclass must implement #handle_send"
  end
end
```

Behaviors:
- HMAC verification using `FALECOM_DISPATCH_HMAC_SECRET`.
- Same HMAC scheme as ingest: `X-FaleCom-Signature` + `X-FaleCom-Timestamp`.
- Standard error responses: 401 (bad HMAC), 422 (validation error), 500 (provider error).
- `/health` endpoint for container health checks.
- Request logging with correlation ID.

### 2.7 `FaleComChannel::Logging`

Structured JSON logging helpers.

```ruby
FaleComChannel.logger.info(
  event: "message_ingested",
  channel_type: "whatsapp_cloud",
  external_id: "wamid.HBg...",
  correlation_id: "abc-123"
)
```

- JSON format to stdout.
- Correlation ID generated per message, flows through consumer → ingest client → Rails.
- Passed via `X-FaleCom-Correlation-Id` header.

### 2.8 HMAC Utilities

Shared between `IngestClient` and `SendServer`:

```ruby
module FaleComChannel::Hmac
  def self.sign(body, secret)
    "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", secret, body)}"
  end

  def self.verify!(request_signature, body, secret, timestamp:, max_age: 300)
    # Verify timestamp is within max_age seconds
    # Verify signature matches
    # Raises FaleComChannel::HmacVerificationError on failure
  end
end
```

---

## 3. What is out of scope?

- **Actual channel containers** — this spec builds only the gem, not the WhatsApp/Z-API/etc. apps that use it.
- **Rails `/internal/ingest` endpoint** — that's the consumer of this gem's contract, built in Spec 4.
- **SQS infrastructure** (queues, DLQs, IAM) — Terraform config is a separate concern.
- **The `inbound_queue` Postgres table in the Rails app** — it's created by the gem's local adapter but only used by channel containers and dev-webhook, not by the Rails app itself. The migration for this table lives in the gem's setup or in the dev-webhook setup, not in Rails migrations.

---

## 4. What changes about the system?

After this spec is executed:

- The `falecom_channel` gem exists at `packages/falecom_channel/` and can be referenced via `gem "falecom_channel", path: "../../falecom_channel"` from any container's Gemfile.
- The Common Ingestion Payload has a machine-enforceable schema — not just a JSON example in ARCHITECTURE.md.
- Channel containers can be built by implementing two methods: `handle(raw_body, headers)` for inbound and `handle_send(payload)` for outbound. Everything else is handled by the gem.
- The local queue adapter enables full-pipeline development without AWS.

No contradictions with the architecture. This spec implements `ARCHITECTURE.md § Shared Infrastructure — falecom_channel gem` and `ARCHITECTURE.md § Queue Adapter`.

---

## 5. Acceptance criteria

1. `cd packages/falecom_channel && bundle exec rspec` — all specs pass.
2. `FaleComChannel::Payload.validate!` accepts a valid inbound message hash matching the ARCHITECTURE.md example.
3. `FaleComChannel::Payload.validate!` rejects a hash missing `channel.type` with a clear error message.
4. `FaleComChannel::QueueAdapter.build(backend: "local", queue_name: "test")` returns a `LocalAdapter`.
5. `LocalAdapter#enqueue` + `LocalAdapter#consume` round-trips a message (integration test with Postgres).
6. `FaleComChannel::IngestClient` signs requests with correct HMAC headers (unit test with Faraday test adapter).
7. `FaleComChannel::SendServer` rejects requests with invalid HMAC (returns 401).
8. `FaleComChannel::Hmac.verify!` rejects timestamps older than 5 minutes.
9. `bundle exec standardrb` passes in the gem directory.

---

## 6. Risks

- **dry-struct / dry-validation learning curve** — these gems have a specific DSL. If the team is unfamiliar, there's a ramp-up cost. Mitigation: the schema is defined once and rarely changes; the DSL is contained to one file.
- **Local adapter reliability** — `SELECT FOR UPDATE SKIP LOCKED` is the right pattern, but it needs careful testing under concurrent consumers. Mitigation: write a concurrent consumer test with multiple threads.
- **Gem dependency weight** — adding `dry-struct`, `dry-validation`, `faraday`, `aws-sdk-sqs`, and `pg` to every channel container increases image size. Mitigation: these are all well-maintained, small gems. The alternative (hand-rolling validation) is worse.

---

## 7. Open questions

1. **dry-struct vs plain Ruby structs** — dry-struct provides type coercion and nested schemas but adds a dependency. Should we consider plain `Struct` + manual validation instead? Recommendation: use dry-validation for the contract (it's the right tool for schema enforcement), but potentially use a simpler struct for the data object itself if dry-struct feels heavy.
2. **`inbound_queue` table location** — should this table be created via a Rake task in the gem, a migration in dev-webhook, or a standalone SQL file? The table is only needed in dev (production uses SQS). Recommendation: the `LocalAdapter` creates the table if it doesn't exist on first use (`CREATE TABLE IF NOT EXISTS`), keeping it self-contained.
