# Plan 04b: Ingestion Pipeline — Container + Infra + E2E

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.
> **Spec:** [04 — Ingestion Pipeline (v2 hardening)](../specs/04-ingestion-pipeline.md)
> **Date:** 2026-04-22
> **Status:** Draft — awaiting approval
> **Branch:** `plan-04a-ingestion-rails` (continues from Plan 04a — same PR)
> **Depends on:** Plan 04a shipped on the branch (commits `e994e5c..30365f5`).

**Goal:** Complete the ingestion pipeline by adding the first channel container (`packages/channels/whatsapp-cloud/`), the `infra/dev-webhook/` local API Gateway mock, LocalStack to `infra/docker-compose.yml`, and an end-to-end spec proving the full path: `dev-webhook → LocalStack SQS → whatsapp-cloud container → live Rails /internal/ingest → DB + event + broadcast`. Plus housekeeping: `Channel has_many :messages` association (surfaced during Plan 04a Task 6), Plan 04a prose fixes.

**Architecture:** Two new deploy units — `infra/dev-webhook/` is a 60-line Roda app that receives provider webhook POSTs on `/webhooks/:channel_type` and puts the raw body on the corresponding LocalStack SQS queue. `packages/channels/whatsapp-cloud/` is the reference channel container: uses the `falecom_channel` gem's `Consumer` mixin (SQS polling + graceful shutdown), adds `Parser` (Meta webhook JSON → Common Ingestion Payload), `SignatureVerifier` (validates `X-Hub-Signature-256` from Meta), `Sender` (common outbound → Meta Graph API v21.0), and a `SendServer` subclass that verifies the dispatch HMAC and routes to `Sender`. Text-only scope per Spec 04 v2.

**Tech Stack:** Ruby 4.0.2, `roda`, `faraday`, `aws-sdk-sqs`, `rack-test` (spec), `webmock` (spec), `puma` (dev-webhook + whatsapp-cloud send server). No new root-level dependencies.

---

## Files to touch

### Create — dev-webhook

- `infra/dev-webhook/.rspec`
- `infra/dev-webhook/Gemfile`
- `infra/dev-webhook/config.ru`
- `infra/dev-webhook/app.rb`
- `infra/dev-webhook/Dockerfile`
- `infra/dev-webhook/spec/spec_helper.rb`
- `infra/dev-webhook/spec/app_spec.rb`

### Create — whatsapp-cloud container

- `packages/channels/whatsapp-cloud/.rspec`
- `packages/channels/whatsapp-cloud/Gemfile`
- `packages/channels/whatsapp-cloud/Dockerfile`
- `packages/channels/whatsapp-cloud/config.ru`
- `packages/channels/whatsapp-cloud/app.rb`
- `packages/channels/whatsapp-cloud/lib/parser.rb`
- `packages/channels/whatsapp-cloud/lib/signature_verifier.rb`
- `packages/channels/whatsapp-cloud/lib/sender.rb`
- `packages/channels/whatsapp-cloud/lib/send_server.rb`
- `packages/channels/whatsapp-cloud/spec/spec_helper.rb`
- `packages/channels/whatsapp-cloud/spec/parser_spec.rb`
- `packages/channels/whatsapp-cloud/spec/signature_verifier_spec.rb`
- `packages/channels/whatsapp-cloud/spec/sender_spec.rb`
- `packages/channels/whatsapp-cloud/spec/send_server_spec.rb`
- `packages/channels/whatsapp-cloud/spec/e2e/pipeline_spec.rb`
- `packages/channels/whatsapp-cloud/spec/support/fixtures.rb` (Meta webhook JSON fixtures)

### Modify — infrastructure

- `infra/docker-compose.yml` — add `localstack`, uncomment `app`, `app-jobs`, `dev-webhook`, `channel-whatsapp-cloud`.
- `packages/app/lib/tasks/sqs.rake` (new) — `sqs:ensure_queues` task; boots two queues (`sqs-whatsapp-cloud`, `sqs-zapi`) idempotently against `AWS_ENDPOINT_URL_SQS`. Called by `bin/setup` and by the e2e spec `before(:all)`.
- `packages/app/bin/setup` — append a `rake sqs:ensure_queues` call before exit (no-op if LocalStack isn't up).

### Modify — housekeeping

- `packages/app/app/models/channel.rb` — add `has_many :messages, dependent: :restrict_with_error`.
- `packages/app/spec/models/channel_spec.rb` — association assertion.
- `docs/plans/04a-2026-04-22-ingestion-pipeline-rails.md` — fix the three prose typos flagged during Plan 04a execution.

---

## Order of operations

Ten tasks. Small-scope, TDD where possible. Each ends with a commit.

1. Compose + LocalStack + `sqs:ensure_queues` rake.
2. `dev-webhook` Roda app.
3. whatsapp-cloud container scaffold (Gemfile, Dockerfile, config.ru, app.rb skeleton).
4. whatsapp-cloud `Parser`.
5. whatsapp-cloud `SignatureVerifier`.
6. whatsapp-cloud `Sender`.
7. whatsapp-cloud `SendServer` subclass.
8. Housekeeping — `Channel has_many :messages` + Plan 04a text fixes.
9. E2E pipeline spec.
10. Final regression sweep + PROGRESS.md + PR.

---

## What could go wrong

- **LocalStack image pull is slow the first time.** ~400 MB. Mitigation: document in the task that first `docker compose pull localstack` may take 2 minutes.
- **Queue URL resolution timing.** `Aws::SQS::Client#get_queue_url` fails if the queue isn't created. `sqs:ensure_queues` runs `CreateQueue` which is idempotent (returns the existing URL if the queue exists).
- **E2E spec fragility.** Rails-in-process via `Rack::Server` blocks threads on the Postgres connection pool. Mitigation: the e2e spec uses `Aws::SQS::Client.new(stub_responses: true)` with a direct in-memory hand-off from dev-webhook enqueue → container consume, combined with WebMock-free Faraday calls to the real Rails via `rack-test`'s `Rack::MockRequest`. This is "e2e" in the "every layer of code runs, no mock between them" sense, not "every container actually booted".
- **Meta signature byte-exactness.** Signing the raw request body works only if the Roda app reads `request.body.read` BEFORE any middleware consumes it. Mitigation: SignatureVerifier takes the raw body as a string, not the Rack request object.

---

## Task 1: LocalStack in compose + `sqs:ensure_queues` rake

**Files:**
- Modify: `infra/docker-compose.yml`
- Create: `packages/app/lib/tasks/sqs.rake`
- Modify: `packages/app/bin/setup`

- [ ] **Step 1: Add the localstack service + uncomment ingestion services in compose**

Open `infra/docker-compose.yml`. Keep the existing `workspace` and `postgres` services. Add a `localstack` service, and uncomment/rewrite the ingestion services. The final shape (after the existing `workspace` + `postgres` blocks):

```yaml
  localstack:
    image: localstack/localstack:3
    ports:
      - "4566:4566"
    environment:
      SERVICES: sqs
      DEFAULT_REGION: us-east-1
    healthcheck:
      test: ["CMD-SHELL", "awslocal sqs list-queues || exit 1"]
      interval: 5s
      timeout: 3s
      retries: 20

  dev-webhook:
    build:
      context: ../infra/dev-webhook
    ports:
      - "4000:4000"
    environment:
      AWS_REGION: us-east-1
      AWS_ACCESS_KEY_ID: test
      AWS_SECRET_ACCESS_KEY: test
      AWS_ENDPOINT_URL_SQS: http://localstack:4566
    depends_on:
      localstack:
        condition: service_healthy

  app:
    build:
      context: ../packages/app
    command: bin/rails server -b 0.0.0.0
    ports:
      - "3000:3000"
    environment:
      DATABASE_URL: postgres://falecom:falecom@postgres:5432/falecom_development
      FALECOM_DISPATCH_HMAC_SECRET: dev-dispatch-secret
      CHANNEL_WHATSAPP_CLOUD_URL: http://channel-whatsapp-cloud:9292
    depends_on:
      postgres:
        condition: service_healthy

  app-jobs:
    build:
      context: ../packages/app
    command: bin/jobs start
    environment:
      DATABASE_URL: postgres://falecom:falecom@postgres:5432/falecom_development
    depends_on:
      postgres:
        condition: service_healthy

  channel-whatsapp-cloud:
    build:
      context: ../packages/channels/whatsapp-cloud
    environment:
      SQS_QUEUE_NAME: sqs-whatsapp-cloud
      AWS_REGION: us-east-1
      AWS_ACCESS_KEY_ID: test
      AWS_SECRET_ACCESS_KEY: test
      AWS_ENDPOINT_URL_SQS: http://localstack:4566
      FALECOM_API_URL: http://app:3000
      FALECOM_DISPATCH_HMAC_SECRET: dev-dispatch-secret
      WHATSAPP_ACCESS_TOKEN: ${WHATSAPP_ACCESS_TOKEN:-dev-placeholder}
    depends_on:
      localstack:
        condition: service_healthy
      app:
        condition: service_started
```

- [ ] **Step 2: Create `packages/app/lib/tasks/sqs.rake`**

```ruby
require "aws-sdk-sqs"

namespace :sqs do
  desc "Create dev SQS queues in LocalStack (idempotent). Uses AWS_ENDPOINT_URL_SQS."
  task :ensure_queues do
    queues = %w[sqs-whatsapp-cloud sqs-zapi]
    client = Aws::SQS::Client.new(region: ENV.fetch("AWS_REGION", "us-east-1"))
    queues.each do |name|
      url = client.create_queue(queue_name: name).queue_url
      puts "SQS queue ready: #{name} → #{url}"
    rescue Aws::SQS::Errors::ServiceError => e
      warn "SQS queue setup failed for #{name}: #{e.message}"
    end
  end
end
```

- [ ] **Step 3: Append `sqs:ensure_queues` to `packages/app/bin/setup`**

Find the last rake/db call in `bin/setup` and append:

```ruby
# Create LocalStack queues (no-op if LocalStack isn't up).
system("bin/rails sqs:ensure_queues", out: File::NULL, err: File::NULL)
```

- [ ] **Step 4: Verify compose parses**

```
docker compose -f infra/docker-compose.yml config > /dev/null && echo OK
```
Expected: `OK`.

- [ ] **Step 5: Pull LocalStack image (first time only)**

```
docker compose -f infra/docker-compose.yml pull localstack
```
Expected: image downloaded. May take ~2 min the first time.

- [ ] **Step 6: Run queue-seed rake against a live LocalStack to sanity-check**

```
docker compose -f infra/docker-compose.yml up -d localstack
docker compose -f infra/docker-compose.yml exec -T localstack awslocal sqs create-queue --queue-name smoke-test
docker compose -f infra/docker-compose.yml exec -T localstack awslocal sqs list-queues
docker compose -f infra/docker-compose.yml down
```
Expected: `smoke-test` queue appears in the list, then compose goes down cleanly.

- [ ] **Step 7: Commit**

```
git add infra/docker-compose.yml packages/app/lib/tasks/sqs.rake packages/app/bin/setup
git commit -m "chore(infra): add LocalStack + uncomment ingestion services + sqs:ensure_queues rake"
```

---

## Task 2: `infra/dev-webhook/` Roda app

**Files:**
- Create: `infra/dev-webhook/Gemfile`, `config.ru`, `app.rb`, `Dockerfile`, `.rspec`, `spec/spec_helper.rb`, `spec/app_spec.rb`

- [ ] **Step 1: Scaffold the app files**

`infra/dev-webhook/Gemfile`:
```ruby
source "https://rubygems.org"

ruby "4.0.2"

gem "roda", "~> 3.85"
gem "rack", "~> 3.1"
gem "puma", "~> 6.4"
gem "aws-sdk-sqs", "~> 1.88"
gem "json"

group :test do
  gem "rspec", "~> 3.13"
  gem "rack-test", "~> 2.1"
end
```

`infra/dev-webhook/config.ru`:
```ruby
require_relative "app"
run DevWebhook.app
```

`infra/dev-webhook/app.rb`:
```ruby
require "roda"
require "aws-sdk-sqs"
require "json"

# Dev-only helper that mimics AWS API Gateway's direct-to-SQS integration.
# Receives a provider webhook POST and enqueues the raw body to the matching
# LocalStack SQS queue. No auth, no DB, no HMAC.
module DevWebhook
  QUEUE_BY_CHANNEL = {
    "whatsapp-cloud" => "sqs-whatsapp-cloud",
    "zapi" => "sqs-zapi"
  }.freeze

  def self.app
    App
  end

  def self.sqs_client
    @sqs_client ||= Aws::SQS::Client.new(region: ENV.fetch("AWS_REGION", "us-east-1"))
  end

  def self.reset_client!
    @sqs_client = nil
  end

  class App < Roda
    route do |r|
      r.on "webhooks", String do |channel_type|
        queue_name = QUEUE_BY_CHANNEL[channel_type]
        r.halt(404, {"Content-Type" => "application/json"}, JSON.generate(error: "unknown_channel_type")) unless queue_name

        r.post do
          raw = r.body.read
          queue_url = DevWebhook.sqs_client.get_queue_url(queue_name: queue_name).queue_url
          DevWebhook.sqs_client.send_message(queue_url: queue_url, message_body: raw)
          response.status = 200
          response["Content-Type"] = "application/json"
          JSON.generate(status: "enqueued", queue: queue_name, bytes: raw.bytesize)
        end
      end
    end
  end
end
```

`infra/dev-webhook/Dockerfile`:
```dockerfile
FROM ruby:4.0.2-slim

WORKDIR /app
COPY Gemfile ./
RUN apt-get update -qq && apt-get install -y --no-install-recommends build-essential git \
  && rm -rf /var/lib/apt/lists/*
RUN bundle install

COPY . .

EXPOSE 4000
CMD ["bundle", "exec", "puma", "-p", "4000", "config.ru"]
```

`infra/dev-webhook/.rspec`:
```
--require spec_helper
--format documentation
```

`infra/dev-webhook/spec/spec_helper.rb`:
```ruby
ENV["AWS_REGION"] ||= "us-east-1"
ENV["AWS_ACCESS_KEY_ID"] ||= "test"
ENV["AWS_SECRET_ACCESS_KEY"] ||= "test"

require "rspec"
require "rack/test"
require_relative "../app"

RSpec.configure do |c|
  c.filter_run_when_matching :focus
  c.expose_dsl_globally = true
  c.before(:each) { DevWebhook.reset_client! }
end
```

- [ ] **Step 2: Write the spec**

`infra/dev-webhook/spec/app_spec.rb`:
```ruby
require "spec_helper"

RSpec.describe DevWebhook::App do
  include Rack::Test::Methods

  def app
    DevWebhook::App
  end

  let(:stub_sqs) { Aws::SQS::Client.new(stub_responses: true) }

  before do
    allow(DevWebhook).to receive(:sqs_client).and_return(stub_sqs)
  end

  it "enqueues the raw body to sqs-whatsapp-cloud for POST /webhooks/whatsapp-cloud" do
    stub_sqs.stub_responses(:get_queue_url, queue_url: "http://localstack:4566/000000000000/sqs-whatsapp-cloud")
    stub_sqs.stub_responses(:send_message, message_id: "m-1", md5_of_message_body: "x")

    post "/webhooks/whatsapp-cloud", '{"event":"message"}', {"CONTENT_TYPE" => "application/json"}

    expect(last_response.status).to eq(200)
    body = JSON.parse(last_response.body)
    expect(body).to include("status" => "enqueued", "queue" => "sqs-whatsapp-cloud")
    expect(body["bytes"]).to be_positive

    sent = stub_sqs.api_requests.find { |req| req[:operation_name] == :send_message }
    expect(sent[:params][:message_body]).to eq('{"event":"message"}')
    expect(sent[:params][:queue_url]).to eq("http://localstack:4566/000000000000/sqs-whatsapp-cloud")
  end

  it "routes POST /webhooks/zapi to sqs-zapi" do
    stub_sqs.stub_responses(:get_queue_url, queue_url: "http://localstack:4566/000000000000/sqs-zapi")
    stub_sqs.stub_responses(:send_message, message_id: "m-2", md5_of_message_body: "y")

    post "/webhooks/zapi", "raw=body", {}

    expect(last_response.status).to eq(200)
  end

  it "returns 404 for unknown channel types" do
    post "/webhooks/telegram", "{}", {"CONTENT_TYPE" => "application/json"}
    expect(last_response.status).to eq(404)
    expect(JSON.parse(last_response.body)).to eq({"error" => "unknown_channel_type"})
  end
end
```

- [ ] **Step 3: `bundle install` inside the workspace**

```
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/infra/dev-webhook && bundle install"
```

- [ ] **Step 4: Run the spec**

```
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/infra/dev-webhook && bundle exec rspec"
```
Expected: 3 examples, 0 failures.

- [ ] **Step 5: Commit**

```
git add infra/dev-webhook
git commit -m "feat(dev-webhook): Roda app that enqueues provider webhooks to LocalStack SQS"
```

---

## Task 3: `packages/channels/whatsapp-cloud/` scaffold

**Files:**
- Create: `Gemfile`, `Dockerfile`, `config.ru`, `app.rb`, `.rspec`, `spec/spec_helper.rb`, `spec/support/fixtures.rb`

- [ ] **Step 1: Create `packages/channels/whatsapp-cloud/Gemfile`**

```ruby
source "https://rubygems.org"

ruby "4.0.2"

gem "falecom_channel", path: "../../falecom_channel"
gem "faraday", "~> 2.12"
gem "rack", "~> 3.1"
gem "puma", "~> 6.4"

group :test do
  gem "rspec", "~> 3.13"
  gem "rack-test", "~> 2.1"
  gem "webmock", "~> 3.24"
end
```

- [ ] **Step 2: `packages/channels/whatsapp-cloud/config.ru`**

```ruby
require_relative "lib/send_server"
run WhatsappCloud::SendServer
```

- [ ] **Step 3: `packages/channels/whatsapp-cloud/app.rb` (entry point — stub until Task 7 wires it)**

```ruby
require "falecom_channel"
require_relative "lib/parser"
require_relative "lib/signature_verifier"
require_relative "lib/sender"

module WhatsappCloud
  class Container
    include FaleComChannel::Consumer

    queue_name ENV.fetch("SQS_QUEUE_NAME", "sqs-whatsapp-cloud")
    concurrency Integer(ENV.fetch("CONCURRENCY", "1"))

    def handle(raw_body, headers)
      raise NotImplementedError, "wired in Task 7"
    end
  end
end

WhatsappCloud::Container.new.start if __FILE__ == $PROGRAM_NAME
```

- [ ] **Step 4: `packages/channels/whatsapp-cloud/Dockerfile`**

```dockerfile
FROM ruby:4.0.2-slim

WORKDIR /app
COPY . .

RUN apt-get update -qq && apt-get install -y --no-install-recommends build-essential git \
  && rm -rf /var/lib/apt/lists/*
RUN bundle install

EXPOSE 9292
CMD ["bundle", "exec", "ruby", "app.rb"]
```

- [ ] **Step 5: `.rspec`, `spec/spec_helper.rb`, `spec/support/fixtures.rb`**

`.rspec`:
```
--require spec_helper
--format documentation
```

`spec/spec_helper.rb`:
```ruby
ENV["AWS_REGION"] ||= "us-east-1"
ENV["AWS_ACCESS_KEY_ID"] ||= "test"
ENV["AWS_SECRET_ACCESS_KEY"] ||= "test"
ENV["FALECOM_API_URL"] ||= "http://rails.test"
ENV["WHATSAPP_APP_SECRET"] ||= "test-app-secret"
ENV["WHATSAPP_ACCESS_TOKEN"] ||= "test-access-token"

require "rspec"
require "rack/test"
require "webmock/rspec"
WebMock.disable_net_connect!

require "falecom_channel"
require_relative "../lib/parser"
require_relative "../lib/signature_verifier"
require_relative "../lib/sender"
require_relative "../lib/send_server"
require_relative "support/fixtures"

RSpec.configure do |c|
  c.filter_run_when_matching :focus
  c.expose_dsl_globally = true
end
```

`spec/support/fixtures.rb` — Meta webhook text-message fixture:
```ruby
module WhatsappCloud::Fixtures
  module_function

  def inbound_text_webhook
    {
      "object" => "whatsapp_business_account",
      "entry" => [{
        "id" => "BUSINESS_ACCOUNT_ID",
        "changes" => [{
          "field" => "messages",
          "value" => {
            "messaging_product" => "whatsapp",
            "metadata" => {
              "display_phone_number" => "15550000001",
              "phone_number_id" => "PHONE_NUMBER_ID"
            },
            "contacts" => [{
              "profile" => {"name" => "João Silva"},
              "wa_id" => "5511988888888"
            }],
            "messages" => [{
              "from" => "5511988888888",
              "id" => "wamid.HBgL1234567890",
              "timestamp" => "1745000000",
              "text" => {"body" => "Olá, tudo bem?"},
              "type" => "text"
            }]
          }
        }]
      }]
    }
  end

  def status_webhook(status: "delivered", external_id: "wamid.HBgL1234567890")
    {
      "object" => "whatsapp_business_account",
      "entry" => [{
        "id" => "BUSINESS_ACCOUNT_ID",
        "changes" => [{
          "field" => "messages",
          "value" => {
            "messaging_product" => "whatsapp",
            "metadata" => {"phone_number_id" => "PHONE_NUMBER_ID"},
            "statuses" => [{
              "id" => external_id,
              "status" => status,
              "timestamp" => "1745000005",
              "recipient_id" => "5511988888888"
            }]
          }
        }]
      }]
    }
  end
end
```

- [ ] **Step 6: `bundle install` inside the workspace**

```
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/channels/whatsapp-cloud && bundle install"
```

- [ ] **Step 7: Commit**

```
git add packages/channels/whatsapp-cloud
git commit -m "chore(whatsapp-cloud): scaffold container — Gemfile, Dockerfile, spec helper, fixtures"
```

---

## Task 4: `WhatsappCloud::Parser` (Meta webhook → Common Ingestion Payload)

**Files:**
- Create: `packages/channels/whatsapp-cloud/lib/parser.rb`
- Create: `packages/channels/whatsapp-cloud/spec/parser_spec.rb`

- [ ] **Step 1: Write the spec first**

`spec/parser_spec.rb`:
```ruby
require "spec_helper"

RSpec.describe WhatsappCloud::Parser do
  let(:channel_identifier) { ENV.fetch("WHATSAPP_PHONE_NUMBER", "+15550000001") }

  describe ".to_common_payload" do
    it "maps a text inbound to the Common Ingestion Payload" do
      raw = JSON.generate(WhatsappCloud::Fixtures.inbound_text_webhook)
      payload = described_class.to_common_payload(raw)

      expect(payload["type"]).to eq("inbound_message")
      expect(payload["channel"]).to eq({"type" => "whatsapp_cloud", "identifier" => "15550000001"})
      expect(payload["contact"]).to include(
        "source_id" => "5511988888888",
        "name" => "João Silva"
      )
      expect(payload["message"]).to include(
        "external_id" => "wamid.HBgL1234567890",
        "direction" => "inbound",
        "content" => "Olá, tudo bem?",
        "content_type" => "text",
        "attachments" => []
      )
      expect(payload["message"]["sent_at"]).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      expect(payload["metadata"]["whatsapp_context"]["phone_number_id"]).to eq("PHONE_NUMBER_ID")
      expect(payload["raw"]).to be_a(Hash)
    end

    it "maps a status update to outbound_status_update" do
      raw = JSON.generate(WhatsappCloud::Fixtures.status_webhook(status: "read"))
      payload = described_class.to_common_payload(raw)

      expect(payload["type"]).to eq("outbound_status_update")
      expect(payload["channel"]).to eq({"type" => "whatsapp_cloud", "identifier" => "PHONE_NUMBER_ID"})
      expect(payload["external_id"]).to eq("wamid.HBgL1234567890")
      expect(payload["status"]).to eq("read")
      expect(payload["timestamp"]).to match(/\A\d{4}-\d{2}-\d{2}T/)
    end

    it "raises UnsupportedContentTypeError for non-text messages" do
      fixture = WhatsappCloud::Fixtures.inbound_text_webhook
      fixture["entry"][0]["changes"][0]["value"]["messages"][0]["type"] = "image"
      fixture["entry"][0]["changes"][0]["value"]["messages"][0].delete("text")

      expect {
        described_class.to_common_payload(JSON.generate(fixture))
      }.to raise_error(WhatsappCloud::Parser::UnsupportedContentTypeError, /image/)
    end
  end
end
```

- [ ] **Step 2: Run — expect failures**

```
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/channels/whatsapp-cloud && bundle exec rspec spec/parser_spec.rb"
```
Expected: `NameError: uninitialized constant WhatsappCloud::Parser`.

- [ ] **Step 3: Implement**

`lib/parser.rb`:
```ruby
require "json"

module WhatsappCloud
  # Meta WhatsApp Cloud webhook → Common Ingestion Payload.
  # Plan 04b scope: text inbound + status updates only.
  class Parser
    class UnsupportedContentTypeError < StandardError; end

    def self.to_common_payload(raw_body)
      json = raw_body.is_a?(String) ? JSON.parse(raw_body) : raw_body
      value = json.dig("entry", 0, "changes", 0, "value") || {}

      if value["statuses"]
        parse_status(value)
      elsif value["messages"]
        parse_inbound(value, raw: json)
      else
        raise UnsupportedContentTypeError, "unknown payload shape"
      end
    end

    def self.parse_inbound(value, raw:)
      message = value.fetch("messages").first
      type = message["type"]

      raise UnsupportedContentTypeError, "unsupported content_type: #{type}" unless type == "text"

      contact = (value["contacts"] || []).first || {}
      metadata = value["metadata"] || {}

      {
        "type" => "inbound_message",
        "channel" => {
          "type" => "whatsapp_cloud",
          "identifier" => metadata.fetch("display_phone_number", metadata["phone_number_id"])
        },
        "contact" => {
          "source_id" => message.fetch("from"),
          "name" => contact.dig("profile", "name"),
          "phone_number" => "+#{message.fetch("from")}"
        },
        "message" => {
          "external_id" => message.fetch("id"),
          "direction" => "inbound",
          "content" => message.dig("text", "body"),
          "content_type" => "text",
          "attachments" => [],
          "sent_at" => Time.at(message.fetch("timestamp").to_i).utc.iso8601,
          "reply_to_external_id" => message.dig("context", "id")
        },
        "metadata" => {
          "whatsapp_context" => {
            "business_account_id" => metadata["business_account_id"],
            "phone_number_id" => metadata["phone_number_id"]
          }
        },
        "raw" => raw
      }
    end

    def self.parse_status(value)
      status = value.fetch("statuses").first
      metadata = value["metadata"] || {}
      {
        "type" => "outbound_status_update",
        "channel" => {
          "type" => "whatsapp_cloud",
          "identifier" => metadata.fetch("display_phone_number", metadata["phone_number_id"])
        },
        "external_id" => status.fetch("id"),
        "status" => status.fetch("status"),
        "timestamp" => Time.at(status.fetch("timestamp").to_i).utc.iso8601,
        "error" => status.dig("errors", 0, "message"),
        "metadata" => {"recipient_id" => status["recipient_id"]}
      }
    end

    private_class_method :parse_inbound, :parse_status
  end
end
```

- [ ] **Step 4: Run — expect all green**

```
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/channels/whatsapp-cloud && bundle exec rspec spec/parser_spec.rb"
```
Expected: 3 examples, 0 failures.

- [ ] **Step 5: Commit**

```
git add packages/channels/whatsapp-cloud/lib/parser.rb packages/channels/whatsapp-cloud/spec/parser_spec.rb
git commit -m "feat(whatsapp-cloud): Parser maps Meta text + status webhooks to Common Payload"
```

---

## Task 5: `WhatsappCloud::SignatureVerifier`

**Files:**
- Create: `packages/channels/whatsapp-cloud/lib/signature_verifier.rb`
- Create: `packages/channels/whatsapp-cloud/spec/signature_verifier_spec.rb`

- [ ] **Step 1: Write the spec**

`spec/signature_verifier_spec.rb`:
```ruby
require "spec_helper"
require "openssl"

RSpec.describe WhatsappCloud::SignatureVerifier do
  let(:secret) { "test-app-secret" }
  let(:raw_body) { '{"object":"whatsapp_business_account","entry":[]}' }
  let(:valid_sig) { "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", secret, raw_body) }

  describe ".verify!" do
    it "returns true for a correct signature" do
      expect(described_class.verify!(raw_body, valid_sig, secret: secret)).to eq(true)
    end

    it "raises SignatureError for a mismatched signature" do
      expect {
        described_class.verify!(raw_body, "sha256=deadbeef", secret: secret)
      }.to raise_error(WhatsappCloud::SignatureVerifier::SignatureError)
    end

    it "raises SignatureError when the signature header is blank" do
      expect {
        described_class.verify!(raw_body, "", secret: secret)
      }.to raise_error(WhatsappCloud::SignatureVerifier::SignatureError)
    end

    it "uses constant-time comparison" do
      expect(OpenSSL).to receive(:secure_compare).and_call_original.at_least(:once)
      begin
        described_class.verify!(raw_body, valid_sig, secret: secret)
      rescue WhatsappCloud::SignatureVerifier::SignatureError
        # swallow — we only care that secure_compare was used
      end
    end
  end
end
```

- [ ] **Step 2: Run — expect NameError**

```
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/channels/whatsapp-cloud && bundle exec rspec spec/signature_verifier_spec.rb"
```

- [ ] **Step 3: Implement**

`lib/signature_verifier.rb`:
```ruby
require "openssl"

module WhatsappCloud
  # Validates Meta's X-Hub-Signature-256 header against the raw request body
  # using HMAC-SHA256 with the WhatsApp app secret. Constant-time comparison
  # so attacker probing can't use timing signal.
  class SignatureVerifier
    class SignatureError < StandardError; end

    def self.verify!(raw_body, header_value, secret: ENV.fetch("WHATSAPP_APP_SECRET"))
      raise SignatureError, "missing signature header" if header_value.to_s.empty?

      provided = header_value.sub(/\Asha256=/, "")
      expected = OpenSSL::HMAC.hexdigest("SHA256", secret, raw_body)

      raise SignatureError, "signature mismatch" unless OpenSSL.secure_compare(expected, provided)

      true
    end
  end
end
```

- [ ] **Step 4: Run — all green**

Expected: 4 examples, 0 failures.

- [ ] **Step 5: Commit**

```
git add packages/channels/whatsapp-cloud/lib/signature_verifier.rb packages/channels/whatsapp-cloud/spec/signature_verifier_spec.rb
git commit -m "feat(whatsapp-cloud): SignatureVerifier with constant-time HMAC-SHA256 compare"
```

---

## Task 6: `WhatsappCloud::Sender`

**Files:**
- Create: `packages/channels/whatsapp-cloud/lib/sender.rb`
- Create: `packages/channels/whatsapp-cloud/spec/sender_spec.rb`

- [ ] **Step 1: Write the spec**

`spec/sender_spec.rb`:
```ruby
require "spec_helper"

RSpec.describe WhatsappCloud::Sender do
  let(:access_token) { "EAAG-test-token" }
  let(:phone_number_id) { "PHONE_NUMBER_ID" }
  let(:sender) { described_class.new(access_token: access_token, phone_number_id: phone_number_id) }
  let(:payload) do
    {
      "type" => "outbound_message",
      "channel" => {"type" => "whatsapp_cloud", "identifier" => "15550000001"},
      "contact" => {"source_id" => "5511988888888"},
      "message" => {
        "internal_id" => 42,
        "content" => "Obrigado pelo contato!",
        "content_type" => "text",
        "attachments" => [],
        "reply_to_external_id" => nil
      },
      "metadata" => {}
    }
  end

  describe "#send_message" do
    let(:endpoint) { "https://graph.facebook.com/v21.0/#{phone_number_id}/messages" }

    it "POSTs to the Meta v21.0 /messages endpoint for a text message" do
      stub_request(:post, endpoint)
        .with(
          headers: {"Authorization" => "Bearer #{access_token}", "Content-Type" => "application/json"},
          body: hash_including(
            "messaging_product" => "whatsapp",
            "to" => "5511988888888",
            "type" => "text",
            "text" => {"body" => "Obrigado pelo contato!"}
          )
        )
        .to_return(status: 200, body: JSON.generate("messages" => [{"id" => "wamid.outbound.123"}]))

      result = sender.send_message(payload)
      expect(result).to eq(external_id: "wamid.outbound.123")
    end

    it "raises for non-text content_type" do
      payload["message"]["content_type"] = "image"
      expect { sender.send_message(payload) }.to raise_error(NotImplementedError, /image/)
    end

    it "raises WhatsappCloud::Sender::SendError on 4xx" do
      stub_request(:post, endpoint).to_return(status: 400, body: JSON.generate("error" => {"message" => "invalid recipient"}))
      expect { sender.send_message(payload) }.to raise_error(WhatsappCloud::Sender::SendError, /invalid recipient/)
    end
  end
end
```

- [ ] **Step 2: Run — NameError**

```
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/channels/whatsapp-cloud && bundle exec rspec spec/sender_spec.rb"
```

- [ ] **Step 3: Implement**

`lib/sender.rb`:
```ruby
require "faraday"
require "json"

module WhatsappCloud
  # Translates the Common outbound payload into a Meta Graph API v21.0 /messages call.
  # Text-only for Plan 04b.
  class Sender
    class SendError < StandardError; end

    BASE_URL = "https://graph.facebook.com/v21.0"

    def initialize(access_token:, phone_number_id:, connection: nil)
      @access_token = access_token
      @phone_number_id = phone_number_id
      @conn = connection || Faraday.new(url: BASE_URL) do |f|
        f.request :json
        f.adapter Faraday.default_adapter
        f.options.timeout = 10
        f.options.open_timeout = 5
      end
    end

    def send_message(payload)
      message = payload.fetch("message")
      content_type = message.fetch("content_type")
      raise NotImplementedError, "content_type: #{content_type} not supported" unless content_type == "text"

      body = {
        messaging_product: "whatsapp",
        to: payload.dig("contact", "source_id"),
        type: "text",
        text: {body: message.fetch("content")}
      }

      response = @conn.post("/v21.0/#{@phone_number_id}/messages") do |req|
        req.headers["Authorization"] = "Bearer #{@access_token}"
        req.headers["Content-Type"] = "application/json"
        req.body = body
      end

      if (200..299).cover?(response.status)
        parsed = response.body.is_a?(String) ? JSON.parse(response.body) : response.body
        {external_id: parsed.dig("messages", 0, "id")}
      else
        parsed = begin
          response.body.is_a?(String) ? JSON.parse(response.body) : response.body
        rescue JSON::ParserError
          {}
        end
        raise SendError, parsed.dig("error", "message") || "send failed (#{response.status})"
      end
    end
  end
end
```

- [ ] **Step 4: Run — all green**

Expected: 3 examples, 0 failures.

- [ ] **Step 5: Commit**

```
git add packages/channels/whatsapp-cloud/lib/sender.rb packages/channels/whatsapp-cloud/spec/sender_spec.rb
git commit -m "feat(whatsapp-cloud): Sender POSTs text to Meta v21.0 /messages, returns external_id"
```

---

## Task 7: `WhatsappCloud::SendServer` subclass + container `#handle`

**Files:**
- Create: `packages/channels/whatsapp-cloud/lib/send_server.rb`
- Create: `packages/channels/whatsapp-cloud/spec/send_server_spec.rb`
- Modify: `packages/channels/whatsapp-cloud/app.rb` (replace the Task 3 stub `#handle`)

- [ ] **Step 1: Write the SendServer spec**

`spec/send_server_spec.rb`:
```ruby
require "spec_helper"

RSpec.describe WhatsappCloud::SendServer do
  include Rack::Test::Methods

  def app
    described_class
  end

  let(:secret) { "test-dispatch-secret" }
  let(:payload) do
    {
      "type" => "outbound_message",
      "channel" => {"type" => "whatsapp_cloud", "identifier" => "15550000001"},
      "contact" => {"source_id" => "5511988888888"},
      "message" => {"internal_id" => 1, "content" => "Oi", "content_type" => "text", "attachments" => []},
      "metadata" => {"channel_credentials" => {"access_token" => "EAAG-x", "phone_number_id" => "PNID"}}
    }
  end

  before do
    ENV["FALECOM_DISPATCH_HMAC_SECRET"] = secret
    described_class.dispatch_secret(secret)
  end

  def signed_headers(body)
    ts = Time.now.to_i.to_s
    sig = FaleComChannel::HmacSigner.sign(body, secret, timestamp: ts.to_i)
    {
      "CONTENT_TYPE" => "application/json",
      "HTTP_X_FALECOM_SIGNATURE" => sig,
      "HTTP_X_FALECOM_TIMESTAMP" => ts
    }
  end

  it "delegates to Sender and returns the external_id on 200" do
    body = JSON.generate(payload)
    expect_any_instance_of(WhatsappCloud::Sender).to receive(:send_message).and_return(external_id: "wamid.abc")

    post "/send", body, signed_headers(body)

    expect(last_response.status).to eq(200)
    expect(JSON.parse(last_response.body)).to eq({"external_id" => "wamid.abc"})
  end

  it "rejects requests with an invalid HMAC signature" do
    body = JSON.generate(payload)
    post "/send", body, {
      "CONTENT_TYPE" => "application/json",
      "HTTP_X_FALECOM_SIGNATURE" => "sha256=deadbeef",
      "HTTP_X_FALECOM_TIMESTAMP" => Time.now.to_i.to_s
    }
    expect(last_response.status).to be >= 400
  end
end
```

- [ ] **Step 2: Implement `lib/send_server.rb`**

```ruby
require "falecom_channel"
require_relative "sender"

module WhatsappCloud
  class SendServer < FaleComChannel::SendServer
    dispatch_secret ENV.fetch("FALECOM_DISPATCH_HMAC_SECRET", "dev-dispatch-secret")

    def handle_send(payload)
      creds = payload.dig("metadata", "channel_credentials") || {}
      sender = Sender.new(
        access_token: creds.fetch("access_token") { ENV.fetch("WHATSAPP_ACCESS_TOKEN") },
        phone_number_id: creds.fetch("phone_number_id") { ENV.fetch("WHATSAPP_PHONE_NUMBER_ID") }
      )
      sender.send_message(payload)
    end
  end
end
```

- [ ] **Step 3: Wire `app.rb#handle` (replaces the Task 3 stub)**

Replace the body of `WhatsappCloud::Container#handle` with:
```ruby
def handle(raw_body, headers)
  signature = headers["X-Hub-Signature-256"] || headers[:x_hub_signature_256]
  SignatureVerifier.verify!(raw_body, signature.to_s)

  payload = Parser.to_common_payload(raw_body)
  FaleComChannel::Payload.validate!(payload.transform_keys(&:to_s))
  ingest_client.post(payload)
end
```

- [ ] **Step 4: Run SendServer spec**

```
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/channels/whatsapp-cloud && bundle exec rspec spec/send_server_spec.rb"
```
Expected: 2 examples, 0 failures. (If the gem's `FaleComChannel::SendServer` has a different `dispatch_secret` API than what the stub assumes, read `packages/falecom_channel/lib/falecom_channel/send_server.rb` and adapt the subclass to match — do NOT modify the gem.)

- [ ] **Step 5: Run the full container suite (all 4 component specs so far)**

```
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/channels/whatsapp-cloud && bundle exec rspec --exclude-pattern 'spec/e2e/**/*'"
```
Expected: 12 examples (3 parser + 4 verifier + 3 sender + 2 send_server), 0 failures.

- [ ] **Step 6: Commit**

```
git add packages/channels/whatsapp-cloud/lib/send_server.rb packages/channels/whatsapp-cloud/spec/send_server_spec.rb packages/channels/whatsapp-cloud/app.rb
git commit -m "feat(whatsapp-cloud): SendServer subclass + Container#handle wiring"
```

---

## Task 8: Housekeeping — `Channel has_many :messages` + Plan 04a text fixes

**Files:**
- Modify: `packages/app/app/models/channel.rb`
- Modify: `packages/app/app/services/ingestion/process_status_update.rb` (switch back to `channel.messages.find_by` for consistency now that the association exists)
- Modify: `packages/app/spec/models/channel_spec.rb`
- Modify: `docs/plans/04a-2026-04-22-ingestion-pipeline-rails.md`

- [ ] **Step 1: Add the association**

In `packages/app/app/models/channel.rb`, inside the `Channel < ApplicationRecord` body, add:
```ruby
has_many :messages, dependent: :restrict_with_error
```

- [ ] **Step 2: Restore `channel.messages.find_by` in `ProcessStatusUpdate`**

In `packages/app/app/services/ingestion/process_status_update.rb`, change the lookup from:
```ruby
message = Message.find_by(channel_id: channel.id, external_id: external_id)
```
back to:
```ruby
message = channel.messages.find_by(external_id: external_id)
```

- [ ] **Step 3: Add an association assertion to the Channel spec**

Append to `packages/app/spec/models/channel_spec.rb`:
```ruby
describe "associations" do
  it "has many messages" do
    association = described_class.reflect_on_association(:messages)
    expect(association).not_to be_nil
    expect(association.macro).to eq(:has_many)
    expect(association.options[:dependent]).to eq(:restrict_with_error)
  end
end
```

- [ ] **Step 4: Fix Plan 04a prose typos**

In `docs/plans/04a-2026-04-22-ingestion-pipeline-rails.md`:
- Task 3 Step 4 "Expected: 9 examples, 0 failures." → "Expected: 8 examples, 0 failures."
- Task 4 Step 4 (summary) "6 examples" → "7 examples".
- Task 6 Step 1 spec — change `it "emits messages:#{status} on a real update"` to `it "emits messages:delivered on a real update"` (the variable `status` is undefined at spec load time; the test body already asserts the literal event name).
- Task 9 Step 1 expected total "~134" → "141".

- [ ] **Step 5: Run the full `packages/app` rspec suite**

```
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && unset DATABASE_URL && bundle exec rspec"
```
Expected: 142 examples (141 + 1 new association spec), 0 failures.

- [ ] **Step 6: standardrb + commit**

```
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && standardrb --fix"
git add packages/app/app/models/channel.rb packages/app/app/services/ingestion/process_status_update.rb packages/app/spec/models/channel_spec.rb docs/plans/04a-2026-04-22-ingestion-pipeline-rails.md
git commit -m "chore(app): add Channel has_many :messages; fix Plan 04a prose typos"
```

---

## Task 9: E2E pipeline spec

**Files:**
- Create: `packages/channels/whatsapp-cloud/spec/e2e/pipeline_spec.rb`

The e2e spec boots LocalStack (via docker compose — must be up when the spec runs), creates the two SQS queues, starts the container's consumer loop in a thread, enqueues a Meta webhook JSON to `sqs-whatsapp-cloud`, and asserts that a WebMock-stubbed `/internal/ingest` receives the correct Common Ingestion Payload. This tests the full container wiring (SQS → Consumer → SignatureVerifier → Parser → IngestClient → Rails) without needing a live Rails server — the Rails side is independently proven by Plan 04a's request spec.

- [ ] **Step 1: Write the e2e spec**

`packages/channels/whatsapp-cloud/spec/e2e/pipeline_spec.rb`:
```ruby
require "spec_helper"
require "aws-sdk-sqs"
require "openssl"
require "json"
require "timeout"

RSpec.describe "WhatsApp Cloud → Rails pipeline", :e2e do
  let(:app_secret) { "test-app-secret" }
  let(:queue_name) { "sqs-whatsapp-cloud-e2e-#{SecureRandom.hex(4)}" }
  let(:sqs) { Aws::SQS::Client.new(region: "us-east-1") }
  let(:queue_url) { sqs.create_queue(queue_name: queue_name).queue_url }

  before do
    # Swap in test-friendly env for the gem's Consumer defaults.
    ENV["SQS_QUEUE_NAME"] = queue_name
    ENV["FALECOM_API_URL"] = "http://rails.test"
    ENV["WHATSAPP_APP_SECRET"] = app_secret
    queue_url
  end

  after do
    sqs.delete_queue(queue_url: queue_url)
  rescue Aws::SQS::Errors::ServiceError
    # best-effort cleanup
  end

  def sign(body)
    "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", app_secret, body)
  end

  it "ingests a signed Meta webhook end-to-end: SQS → Parser → IngestClient → Rails" do
    webhook = JSON.generate(WhatsappCloud::Fixtures.inbound_text_webhook)

    sqs.send_message(
      queue_url: queue_url,
      message_body: webhook,
      message_attributes: {
        "X-Hub-Signature-256" => {string_value: sign(webhook), data_type: "String"}
      }
    )

    received = nil
    stub_request(:post, "http://rails.test/internal/ingest").with { |req|
      received = JSON.parse(req.body)
      true
    }.to_return(status: 200, body: JSON.generate(status: "ok", message_id: 99))

    container = Class.new(WhatsappCloud::Container).new

    thread = Thread.new { container.start(install_signal_traps: false) }

    Timeout.timeout(8) do
      sleep 0.2 while received.nil?
    end

    container.shutdown!
    thread.join(2)

    expect(received).to include(
      "type" => "inbound_message",
      "channel" => a_hash_including("type" => "whatsapp_cloud")
    )
    expect(received.dig("message", "content")).to eq("Olá, tudo bem?")
    expect(received.dig("message", "content_type")).to eq("text")
  end
end
```

Header-extraction note: the gem's `Consumer#worker_loop` passes `message_attributes` into `handle(body, headers)` after extracting `string_value`. The container's `#handle` (Task 7) reads `headers["X-Hub-Signature-256"]` from that hash.

- [ ] **Step 2: Ensure LocalStack is up for the run**

```
docker compose -f infra/docker-compose.yml up -d localstack
```
Wait ~10s for the healthcheck (`docker compose ... ps localstack` should show `healthy`).

- [ ] **Step 3: Run the e2e spec**

```
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/channels/whatsapp-cloud && AWS_ENDPOINT_URL_SQS=http://localstack:4566 AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test bundle exec rspec spec/e2e/pipeline_spec.rb"
```
Expected: 1 example, 0 failures. Typical runtime: 2–5 seconds.

- [ ] **Step 4: Tear down LocalStack**

```
docker compose -f infra/docker-compose.yml down
```

- [ ] **Step 5: Commit**

```
git add packages/channels/whatsapp-cloud/spec/e2e/pipeline_spec.rb
git commit -m "test(whatsapp-cloud): e2e pipeline spec — LocalStack SQS → Consumer → Rails"
```

---

## Task 10: Final regression + `docs/PROGRESS.md` + PR

- [ ] **Step 1: Full `packages/app` rspec** (should be 142 examples, green).

- [ ] **Step 2: Full `packages/falecom_channel` rspec** (should be 117 examples, green).

- [ ] **Step 3: Full `packages/channels/whatsapp-cloud` rspec** (includes all component specs; excludes e2e by default unless LocalStack is running):
```
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/channels/whatsapp-cloud && bundle exec rspec --exclude-pattern 'spec/e2e/**/*'"
```
Expected: 12 examples, 0 failures.

- [ ] **Step 4: Full `infra/dev-webhook` rspec** (3 examples, green).

- [ ] **Step 5: standardrb across every package**:
- `packages/app`: globally-installed `standardrb` from inside `cd packages/app`.
- `packages/falecom_channel`: `bundle exec standardrb`.
- Other packages (dev-webhook + whatsapp-cloud): globally-installed `standardrb` from inside each package dir (they don't declare `standard` in their Gemfiles).

- [ ] **Step 6: Update `docs/PROGRESS.md`**:

- **Specs** table: Spec 04 moves from `In Progress` → `In Progress` (stays — flips to `Shipped` after PR merge in a follow-up commit).
- **Plans** table: add a row for Plan 04b:
  ```
  | 04b | [Phase 4B — Ingestion Container + Infra](./plans/04b-2026-04-22-ingestion-pipeline-container.md) | 04   | In Progress | —          | —          |
  ```
- Flip Plan 04a to `In Progress` (already done in Plan 04a Task 9).

- [ ] **Step 7: Commit and push**

```
git add docs/PROGRESS.md
git commit -m "docs(progress): Plan 04b in progress"
git push origin plan-04a-ingestion-rails
```

- [ ] **Step 8: Open the PR**

```
gh pr create --base main --head plan-04a-ingestion-rails --title "Spec 04 — Ingestion Pipeline (Plans 04a + 04b + housekeeping)" --body "$(cat <<'EOF'
## Summary

Implements the full ingestion pipeline: Rails `/internal/ingest` + services (04a) and the first channel container, dev-webhook helper, LocalStack dev SQS, and end-to-end test (04b), plus housekeeping (Channel has_many :messages, Plan 04a prose fixes).

- **04a (Rails side)** — `Internal::IngestController`, `Ingestion::ProcessMessage` / `ProcessStatusUpdate`, `Contacts::Resolve`, `Conversations::ResolveOrCreate` (with `pg_advisory_xact_lock(hashtext('display_id'))`), `Messages::Create` (kwargs + `#duplicate?` sentinel), `rake ingest:mock`.
- **04b (container + infra)** — `infra/dev-webhook/` Roda app, `packages/channels/whatsapp-cloud/` with `Parser` + `SignatureVerifier` + `Sender` + `SendServer`, LocalStack + `sqs:ensure_queues`, e2e pipeline spec.
- **Housekeeping** — `Channel has_many :messages` (surfaced during Plan 04a Task 6), Plan 04a prose typo fixes.

## Spec

[Spec 04 v2 — Ingestion Pipeline](../docs/specs/04-ingestion-pipeline.md)

## Plans

- [Plan 04a](../docs/plans/04a-2026-04-22-ingestion-pipeline-rails.md)
- [Plan 04b](../docs/plans/04b-2026-04-22-ingestion-pipeline-container.md)

## Test plan

- [ ] CI green: `packages/app` rspec (142), `packages/falecom_channel` rspec (117), `packages/channels/whatsapp-cloud` rspec non-e2e (12), `infra/dev-webhook` rspec (3).
- [ ] Local e2e: `docker compose -f infra/docker-compose.yml up -d localstack && docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/channels/whatsapp-cloud && AWS_ENDPOINT_URL_SQS=http://localstack:4566 AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test bundle exec rspec spec/e2e/pipeline_spec.rb"`.
- [ ] Local smoke: `bin/rails 'ingest:mock[PR smoke test]'` persists a Message with the expected attributes.
- [ ] standardrb clean across every package.

## Risk

Medium. This is the first PR that touches Rails + a new container + LocalStack + compose in the same change. Rollback: revert the merge commit — main goes back to `94c8ab8` and the ingestion surface disappears. No migrations are introduced, so no DB state issues.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## What this plan does NOT do

- **Admin UI for channel CRUD** — Spec 06.
- **Outbound dispatch (`SendMessageJob` + reply form)** — Spec 05.
- **Other channel containers (Z-API, Evolution, Instagram, Telegram)** — each gets its own spec.
- **Terraform for real AWS** — separate infra spec.
- **Dashboard UI partials (`dashboard/messages/_message.html.erb`, `_status.html.erb`)** — the `Ingestion::ProcessMessage` / `ProcessStatusUpdate` broadcasts will continue to raise `ActionView::MissingTemplate` and get swallowed by their `rescue` blocks until Spec 06 ships the dashboard views.
- **Non-text content types (image, audio, video, document, location, interactive)** — deferred per Spec 04 v2 scope cut. `Parser` raises `UnsupportedContentTypeError`; `Sender` raises `NotImplementedError`.
