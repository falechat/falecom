# falecom_channel

Shared Ruby gem for every FaleCom channel container (WhatsApp Cloud, Z-API,
Evolution, Instagram, Telegram). Owns the **Common Ingestion Payload**
schema — the single contract between channel containers and the Rails app.

Path-dependency only. Never published to RubyGems.

## What's inside

| Module | Purpose |
|---|---|
| `FaleComChannel::Payload` | Common Ingestion Payload schema (dry-struct + dry-validation). `validate!`, `valid?`, `parse`. Schemas: `InboundMessage`, `OutboundStatusUpdate`, `OutboundMessage` |
| `FaleComChannel::QueueAdapter` | SQS wrapper. `consume/ack/nack/enqueue`. Abstract interface; only `SqsAdapter` ships today |
| `FaleComChannel::Consumer` | Mixin for channel container classes. Worker threads, graceful SIGTERM/SIGINT shutdown, per-message correlation id |
| `FaleComChannel::IngestClient` | Faraday client for `POST /internal/ingest`. Retries 5xx (3x, exponential backoff). HMAC-signed with `FALECOM_INGEST_HMAC_SECRET` |
| `FaleComChannel::DispatchClient` | Faraday client for `POST {container}/send`. No retries (Solid Queue retries). HMAC-signed with `FALECOM_DISPATCH_HMAC_SECRET`. 30s read timeout |
| `FaleComChannel::SendServer` | Roda base for the `/send` endpoint. HMAC-verifies inbound, validates payload, dispatches to `#handle_send` |
| `FaleComChannel::HmacSigner` | `sign` + `verify!` for the shared HMAC scheme (sha256, 5-minute tolerance, constant-time compare) |
| `FaleComChannel::Logging` | Structured JSON logger + thread-local correlation-id propagation |

## Usage — channel container

```ruby
# packages/channels/whatsapp-cloud/app.rb
require "falecom_channel"
require_relative "lib/parser"
require_relative "lib/signature_verifier"

class WhatsappCloudContainer
  include FaleComChannel::Consumer

  queue_name ENV.fetch("SQS_QUEUE_NAME")
  concurrency Integer(ENV.fetch("CONCURRENCY", 1))

  def handle(raw_body, headers)
    SignatureVerifier.verify!(raw_body, headers)       # channel-specific
    payload = Parser.new(raw_body).to_common_payload   # channel-specific
    FaleComChannel::Payload.validate!(payload)         # from gem
    ingest_client.post(payload)                        # from gem
  end
end

WhatsappCloudContainer.new.start if __FILE__ == $PROGRAM_NAME
```

The `/send` endpoint is equally thin:

```ruby
class WhatsappCloudSendServer < FaleComChannel::SendServer
  dispatch_secret ENV.fetch("FALECOM_DISPATCH_HMAC_SECRET")

  def handle_send(payload)
    external_id = MetaGraphApi.send_message(payload)
    {external_id: external_id}
  end
end

run WhatsappCloudSendServer
```

## Environment variables

| Var | Used by | Notes |
|---|---|---|
| `SQS_QUEUE_NAME` | `Consumer` | Name (not URL) of the SQS queue. Adapter resolves URL lazily via `GetQueueUrl` |
| `AWS_REGION` | `QueueAdapter::SqsAdapter` | Standard AWS SDK env var |
| `AWS_ENDPOINT_URL_SQS` | `QueueAdapter::SqsAdapter` | Override endpoint (use `http://localstack:4566` in dev) |
| `FALECOM_API_URL` | `Consumer#ingest_client` default | Base URL of the Rails app |
| `FALECOM_INGEST_HMAC_SECRET` | `Consumer#ingest_client` default | Shared secret with Rails `/internal/ingest` |
| `FALECOM_DISPATCH_HMAC_SECRET` | `SendServer` + Rails `DispatchClient` | Shared secret with Rails for `/send` |
| `CONCURRENCY` | Channel container (convention) | Number of worker threads. Default `1` |

## Versioning

Breaking changes to the Common Ingestion Payload bump the gem's **major**
version and require coordinated updates across every channel container in
the same PR. CI enforces that all containers build green before a gem-touching
PR can merge.

Current version: `FaleComChannel::VERSION`.

## Development

All commands run inside the `falecom-workspace-1` container:

```
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/falecom_channel && bundle exec rspec"
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/falecom_channel && bundle exec standardrb"
```

Specs use `Aws::SQS::Client.new(stub_responses: true)` — no live AWS or
LocalStack needed. The first channel container (Spec 04) will add LocalStack
to `infra/docker-compose.yml` for end-to-end dev runs.
