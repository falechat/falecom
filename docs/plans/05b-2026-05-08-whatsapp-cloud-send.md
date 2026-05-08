# Plan 05b: WhatsApp Cloud `/send` — Container Wiring + Integration

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> **Spec:** [05 — Outbound Dispatch](../specs/05-outbound-dispatch.md)
> **Date:** 2026-05-08
> **Status:** Draft — awaiting approval
> **Branch:** `plan-05b-whatsapp-cloud-send`

**Goal:** Make the existing `WhatsappCloud::SendServer` + `WhatsappCloud::Sender` (created during Plan 04b) actually serve outbound traffic from the Rails app: expose the Roda send server on an HTTP port via `docker-compose`, wire `CHANNEL_WHATSAPP_CLOUD_URL` into the Rails workspace, harden the Sender's error mapping, and prove the full Rails → container → Meta API path with a real Faraday round-trip in an integration spec (Meta API itself is stubbed). After this plan, `Dispatch::Outbound.call(...)` from Plan 05a flows through a real container in dev and CI integration tests, end-to-end.

**Architecture:** The container today only boots the SQS consumer (`app.rb`). Its `config.ru` already mounts `WhatsappCloud::SendServer`; we add a Puma config + a `command: bundle exec puma` service in `docker-compose.yml` so the container exposes port 9292 alongside the consumer. HMAC verification on `/send` uses the existing `FaleComChannel::SendServer.dispatch_secret` — same secret as `FALECOM_DISPATCH_HMAC_SECRET` on the Rails side. Sender error mapping converts Meta-specific HTTP status codes into structured errors so `SendMessageJob` can decide retry vs. terminal failure correctly.

**Tech Stack:** Ruby 4.0.2, Roda (already in container), Puma 6.x, Faraday 2.x, RSpec, `falecom_channel` gem, Docker Compose. WebMock for Meta API stubs in container specs; real Faraday round-trip from Rails to a live container booted by `docker compose up channel-whatsapp-cloud-send` in the Rails integration spec.

---

## Files to touch

### Modify

- `packages/channels/whatsapp-cloud/Gemfile` — add `gem "puma"` if not pinned, add `gem "rack"` if missing.
- `packages/channels/whatsapp-cloud/config.ru` — already runs `WhatsappCloud::SendServer`; verify only.
- `packages/channels/whatsapp-cloud/lib/sender.rb` — distinguish retryable (5xx, network) from terminal (4xx) errors via a typed exception hierarchy.
- `packages/channels/whatsapp-cloud/spec/sender_spec.rb` — add cases for 4xx vs 5xx vs network failure.
- `packages/channels/whatsapp-cloud/spec/send_server_spec.rb` — add a case proving `metadata.channel_credentials` is consumed correctly when present in payload.
- `infra/docker-compose.yml` — add `channel-whatsapp-cloud-send` service that runs `bundle exec puma -p 9292 -C config/puma.rb` against the `whatsapp-cloud` image; expose port to the workspace network.
- `packages/app/.env.development` — add `CHANNEL_WHATSAPP_CLOUD_URL=http://channel-whatsapp-cloud-send:9292`.
- `packages/app/.env.test` — add `CHANNEL_WHATSAPP_CLOUD_URL=http://channel-whatsapp-cloud-send:9292` (only used by the integration spec; unit specs stub the client).

### Create

- `packages/channels/whatsapp-cloud/config/puma.rb` — minimal Puma config (1 worker, 5 threads, port from `PORT` env, defaults to 9292).
- `packages/app/spec/integration/outbound_dispatch_spec.rb` — boots the container service via `docker compose up -d channel-whatsapp-cloud-send`, stubs Meta API at the network layer with WebMock-against-the-container-process is impractical; instead we stub Meta API inside the container by running it with `META_API_BASE=http://meta-stub:443` and a tiny `meta-stub` Roda fixture service in `infra/dev-webhook` (already there for inbound; extend for outbound).
- `infra/dev-webhook/lib/meta_stub.rb` — minimal Roda app: returns `{messages:[{id:"wamid.test-1"}]}` on `POST /v21.0/:phone_number_id/messages`.

---

## Order of operations (TDD wave)

1. **Sender error hierarchy** — refactor `WhatsappCloud::Sender::SendError` into `RetryableSendError` + `TerminalSendError`. Update existing spec, add new cases.
2. **Send server credential injection spec** — verify `metadata.channel_credentials` path exists and the `ENV` fallback fires only when missing.
3. **Puma config + Dockerfile entrypoint** — boot Puma alongside the consumer.
4. **Compose service** — add `channel-whatsapp-cloud-send`.
5. **Meta stub** — extend `dev-webhook` (or add a new `meta-stub` Roda service) to fake Meta v21 `/messages`.
6. **Rails integration spec** — Faraday round-trip from Rails container → send server container → meta-stub. Asserts `Message#external_id == "wamid.test-1"`, `status == "sent"`.
7. **Regression sweep** — `rspec` in `packages/app`, `rspec` in `packages/channels/whatsapp-cloud`, `standardrb` both.

---

## What could go wrong

**Most likely:** the integration spec is flaky on first boot — Puma takes 1-2s to start. Mitigation: add a `wait-for-it` loop in the spec's `before(:all)` that polls `GET /health` (Roda default returns 404 — add a tiny `r.get("health") { "ok" }` to `WhatsappCloud::SendServer`). Hard timeout 10s; fail loudly.

**Least likely:** Meta returns success but with a malformed body and `Sender#send_message` raises `KeyError` on `parsed.dig("messages", 0, "id")` returning `nil`. Already handled via `parsed.dig` — but worth a regression test: 200 OK with `{}` body should raise `TerminalSendError`, not `KeyError`. Cover in Task 1.

---

## Task 1: Sender error hierarchy

**Files:**
- Modify: `packages/channels/whatsapp-cloud/lib/sender.rb`
- Modify: `packages/channels/whatsapp-cloud/spec/sender_spec.rb`

- [ ] **Step 1: Add the failing test cases**

Append to `spec/sender_spec.rb`:

```ruby
describe "error mapping" do
  it "raises RetryableSendError on 5xx" do
    conn = Faraday.new { |b| b.adapter :test do |s| s.post(/messages/) { [503, {}, '{"error":{"message":"upstream"}}'] } end }
    sender = described_class.new(access_token: "t", phone_number_id: "p", connection: conn)
    expect { sender.send_message(payload_for("hi")) }.to raise_error(described_class::RetryableSendError, /upstream/)
  end

  it "raises TerminalSendError on 4xx" do
    conn = Faraday.new { |b| b.adapter :test do |s| s.post(/messages/) { [400, {}, '{"error":{"message":"invalid number"}}'] } end }
    sender = described_class.new(access_token: "t", phone_number_id: "p", connection: conn)
    expect { sender.send_message(payload_for("hi")) }.to raise_error(described_class::TerminalSendError, /invalid number/)
  end

  it "raises TerminalSendError when 200 OK has no messages id" do
    conn = Faraday.new { |b| b.adapter :test do |s| s.post(/messages/) { [200, {}, "{}"] } end }
    sender = described_class.new(access_token: "t", phone_number_id: "p", connection: conn)
    expect { sender.send_message(payload_for("hi")) }.to raise_error(described_class::TerminalSendError, /missing.*id/i)
  end
end

def payload_for(content)
  {"contact" => {"source_id" => "55119"}, "message" => {"content" => content, "content_type" => "text"}}
end
```

- [ ] **Step 2: Run, verify all three fail**

Run: `cd packages/channels/whatsapp-cloud && bundle exec rspec spec/sender_spec.rb`
Expected: 3 failures (`uninitialized constant RetryableSendError`, etc.).

- [ ] **Step 3: Update `lib/sender.rb`**

```ruby
module WhatsappCloud
  class Sender
    class SendError < StandardError; end
    class RetryableSendError < SendError; end
    class TerminalSendError < SendError; end

    BASE_URL = "https://graph.facebook.com"

    def initialize(access_token:, phone_number_id:, connection: nil)
      @access_token = access_token
      @phone_number_id = phone_number_id
      @conn = connection || default_connection
    end

    def send_message(payload)
      message = payload.fetch("message")
      content_type = message.fetch("content_type")
      raise TerminalSendError, "content_type: #{content_type} not supported" unless content_type == "text"

      response = @conn.post("/v21.0/#{@phone_number_id}/messages") do |req|
        req.headers["Authorization"] = "Bearer #{@access_token}"
        req.body = build_body(payload, message)
      end

      handle_response(response)
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      raise RetryableSendError, e.message
    end

    private

    def build_body(payload, message)
      {
        messaging_product: "whatsapp",
        to: payload.dig("contact", "source_id"),
        type: "text",
        text: {body: message.fetch("content")}
      }
    end

    def handle_response(response)
      parsed = parse(response.body)
      status = response.status

      if (200..299).cover?(status)
        id = parsed.dig("messages", 0, "id")
        raise TerminalSendError, "missing message id in response" unless id
        {external_id: id}
      elsif (500..599).cover?(status)
        raise RetryableSendError, parsed.dig("error", "message") || "send failed (#{status})"
      else
        raise TerminalSendError, parsed.dig("error", "message") || "send failed (#{status})"
      end
    end

    def parse(body)
      body.is_a?(String) ? JSON.parse(body) : body.to_h
    rescue JSON::ParserError
      {}
    end

    def default_connection
      Faraday.new(url: BASE_URL) do |f|
        f.request :json
        f.adapter Faraday.default_adapter
        f.options.timeout = 10
        f.options.open_timeout = 5
      end
    end
  end
end
```

- [ ] **Step 4: Run, verify pass**

Run: `bundle exec rspec spec/sender_spec.rb`
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add packages/channels/whatsapp-cloud/lib/sender.rb \
        packages/channels/whatsapp-cloud/spec/sender_spec.rb
git commit -m "feat(whatsapp-cloud): split Sender errors into Retryable vs Terminal"
```

---

## Task 2: Send server credential injection regression

**Files:**
- Modify: `packages/channels/whatsapp-cloud/spec/send_server_spec.rb`

- [ ] **Step 1: Add a focused spec asserting the credential resolution order**

```ruby
it "uses metadata.channel_credentials when present, ignoring ENV" do
  ClimateControl.modify("WHATSAPP_ACCESS_TOKEN" => "env-tok", "WHATSAPP_PHONE_NUMBER_ID" => "env-pn") do
    fake_sender = instance_double(WhatsappCloud::Sender, send_message: {external_id: "x"})
    expect(WhatsappCloud::Sender).to receive(:new)
      .with(access_token: "from-meta", phone_number_id: "pn-from-meta")
      .and_return(fake_sender)

    payload = build_outbound_payload(channel_credentials: {"access_token" => "from-meta", "phone_number_id" => "pn-from-meta"})
    post "/send", payload.to_json, signed_headers(payload)

    expect(last_response.status).to eq(200)
  end
end

it "falls back to ENV when channel_credentials missing" do
  ClimateControl.modify("WHATSAPP_ACCESS_TOKEN" => "env-tok", "WHATSAPP_PHONE_NUMBER_ID" => "env-pn") do
    fake_sender = instance_double(WhatsappCloud::Sender, send_message: {external_id: "x"})
    expect(WhatsappCloud::Sender).to receive(:new)
      .with(access_token: "env-tok", phone_number_id: "env-pn")
      .and_return(fake_sender)

    payload = build_outbound_payload(channel_credentials: nil)
    post "/send", payload.to_json, signed_headers(payload)
    expect(last_response.status).to eq(200)
  end
end
```

(`build_outbound_payload` and `signed_headers` go in `spec/support/fixtures.rb`. If they already exist for inbound, extend; otherwise add them — keep them small and obvious.)

- [ ] **Step 2: Run, verify fails until support helpers exist**

Run: `bundle exec rspec spec/send_server_spec.rb`
Expected: FAIL — missing helpers or assertion mismatch.

- [ ] **Step 3: Add helpers + adjust `lib/send_server.rb` only if the resolution order is wrong**

The current `handle_send` reads `meta[:channel_credentials] || meta["channel_credentials"] || {}` and falls back to `ENV.fetch`. Confirm this matches the spec; if it does, no `lib` changes needed — just helpers.

- [ ] **Step 4: Verify pass + commit**

```bash
git add packages/channels/whatsapp-cloud/spec
git commit -m "test(whatsapp-cloud): pin credential resolution order in /send"
```

---

## Task 3: Puma config + container exposes port

**Files:**
- Create: `packages/channels/whatsapp-cloud/config/puma.rb`
- Modify: `packages/channels/whatsapp-cloud/Gemfile` (add `puma` if missing)
- Modify: `packages/channels/whatsapp-cloud/Dockerfile` — expose 9292
- Modify: `packages/channels/whatsapp-cloud/lib/send_server.rb` — add `r.get("health") { response.status = 200; "ok" }` for readiness checks

- [ ] **Step 1: Add Puma config**

```ruby
# config/puma.rb
port ENV.fetch("PORT", 9292)
threads ENV.fetch("PUMA_MIN_THREADS", 1).to_i, ENV.fetch("PUMA_MAX_THREADS", 5).to_i
workers ENV.fetch("PUMA_WORKERS", 1).to_i
preload_app! if ENV.fetch("PUMA_WORKERS", 1).to_i > 1
```

- [ ] **Step 2: Add `gem "puma"` to Gemfile if absent, then `bundle install` inside the container directory**

```bash
cd packages/channels/whatsapp-cloud && bundle install
```

- [ ] **Step 3: Add `/health` route to `lib/send_server.rb`**

Inside the existing `route` block (the FaleComChannel base class exposes a Roda hook — check `packages/falecom_channel/lib/falecom_channel/send_server.rb` for the right extension point). If the base class has no health hook, override `route` in the subclass minimally:

```ruby
def route(r)
  r.get("health") { "ok" }
  super
end
```

- [ ] **Step 4: Add a spec for `/health`** in `spec/send_server_spec.rb`:

```ruby
it "responds 200 to GET /health" do
  get "/health"
  expect(last_response.status).to eq(200)
  expect(last_response.body).to eq("ok")
end
```

- [ ] **Step 5: Run all container specs, verify pass**

```bash
bundle exec rspec
```

Expected: all green.

- [ ] **Step 6: Update Dockerfile**

Add `EXPOSE 9292` and confirm the image already contains `config.ru` + `config/puma.rb` (default Roda Dockerfile from Plan 04b should already COPY the whole directory).

- [ ] **Step 7: Commit**

```bash
git add packages/channels/whatsapp-cloud
git commit -m "feat(whatsapp-cloud): add /health, Puma config, expose 9292"
```

---

## Task 4: Compose service for the send server

**Files:**
- Modify: `infra/docker-compose.yml`

- [ ] **Step 1: Add the service**

```yaml
channel-whatsapp-cloud-send:
  build:
    context: ../packages/channels/whatsapp-cloud
  command: bundle exec puma -C config/puma.rb
  environment:
    FALECOM_DISPATCH_HMAC_SECRET: dev-dispatch-secret
    META_API_BASE: http://meta-stub:4000
    PORT: 9292
  ports:
    - "9292:9292"
  depends_on:
    - meta-stub
  networks:
    - falecom
```

(The existing `channel-whatsapp-cloud` consumer service stays as-is. Send server is a separate process; both share the same image but different `command`s.)

- [ ] **Step 2: Boot it, verify health**

```bash
docker compose -f infra/docker-compose.yml up -d channel-whatsapp-cloud-send
curl -fsS http://localhost:9292/health
```

Expected: `ok`. If port conflict, use `9293` and update `.env.development`.

- [ ] **Step 3: Commit**

```bash
git add infra/docker-compose.yml
git commit -m "chore(infra): add channel-whatsapp-cloud-send compose service"
```

---

## Task 5: Meta API stub

**Files:**
- Create: `infra/dev-webhook/lib/meta_stub.rb` — or a new `infra/meta-stub/` Roda app if `dev-webhook` is already mono-purpose. Pick the smallest delta; if `dev-webhook` is already a single Roda class, add a route there guarded by `Host: meta-stub`.
- Modify: `infra/docker-compose.yml` — add the `meta-stub` service.

- [ ] **Step 1: Add the Roda route**

```ruby
# infra/meta-stub/app.rb
require "roda"
require "json"

class MetaStub < Roda
  route do |r|
    r.post "v21.0", String, "messages" do |_phone_number_id|
      response["Content-Type"] = "application/json"
      JSON.dump(messages: [{id: "wamid.test-#{SecureRandom.hex(4)}"}])
    end

    r.get("health") { "ok" }
  end
end

run MetaStub
```

- [ ] **Step 2: Compose service**

```yaml
meta-stub:
  build:
    context: ../infra/meta-stub
  ports:
    - "4000:4000"
  command: bundle exec puma -p 4000
  networks:
    - falecom
```

- [ ] **Step 3: Wire `META_API_BASE` into `WhatsappCloud::Sender`**

The current `Sender::BASE_URL` is hardcoded to `https://graph.facebook.com`. Make it read `ENV.fetch("META_API_BASE", "https://graph.facebook.com")`. Add a spec confirming the override is honored.

- [ ] **Step 4: Boot + smoke test**

```bash
docker compose up -d meta-stub channel-whatsapp-cloud-send
curl -fsS http://localhost:4000/health
```

Expected: `ok`.

- [ ] **Step 5: Commit**

```bash
git add infra/meta-stub infra/docker-compose.yml packages/channels/whatsapp-cloud
git commit -m "feat(infra): add meta-stub service for outbound integration tests"
```

---

## Task 6: Rails integration spec — full Faraday round-trip

**Files:**
- Create: `packages/app/spec/integration/outbound_dispatch_spec.rb`

- [ ] **Step 1: Write the spec**

```ruby
require "rails_helper"

RSpec.describe "Outbound dispatch end-to-end", :integration do
  let(:user) { create(:user) }
  let(:channel) { create(:channel, channel_type: "whatsapp_cloud", credentials: {access_token: "tok", phone_number_id: "pn-1"}) }
  let(:contact_channel) { create(:contact_channel, channel: channel, source_id: "55119") }
  let(:conversation) { create(:conversation, channel: channel, contact_channel: contact_channel) }

  before(:all) do
    raise "set CHANNEL_WHATSAPP_CLOUD_URL" unless ENV["CHANNEL_WHATSAPP_CLOUD_URL"]
    Timeout.timeout(10) do
      loop do
        Net::HTTP.get_response(URI.join(ENV["CHANNEL_WHATSAPP_CLOUD_URL"], "/health")) rescue (sleep 0.5; next)
        break
      end
    end
  end

  it "delivers an outbound text message through the live container", :slow do
    perform_enqueued_jobs do
      Dispatch::Outbound.call(conversation: conversation, content: "ping", actor: user)
    end

    msg = Message.where(conversation: conversation).order(:id).last
    expect(msg.status).to eq("sent")
    expect(msg.external_id).to start_with("wamid.test-")
  end
end
```

- [ ] **Step 2: Tag integration in `spec/rails_helper.rb` so unit runs skip it by default**

```ruby
config.filter_run_excluding integration: true unless ENV["RUN_INTEGRATION"] == "1"
```

- [ ] **Step 3: Run with the live containers**

```bash
docker compose up -d meta-stub channel-whatsapp-cloud-send
RUN_INTEGRATION=1 bundle exec rspec spec/integration/outbound_dispatch_spec.rb
```

Expected: 1 example, 0 failures.

- [ ] **Step 4: Commit**

```bash
git add packages/app/spec/integration packages/app/spec/rails_helper.rb
git commit -m "test(integration): outbound dispatch end-to-end via live container"
```

---

## Task 7: Regression sweep + PROGRESS.md

- [ ] **Step 1: All test suites**

```bash
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && bundle exec rspec"
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/channels/whatsapp-cloud && bundle exec rspec"
RUN_INTEGRATION=1 docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && bundle exec rspec spec/integration"
```

- [ ] **Step 2: standardrb both packages**

```bash
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && bin/standardrb --fix"
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/channels/whatsapp-cloud && bundle exec standardrb --fix"
```

- [ ] **Step 3: Update PROGRESS.md** — add 05b row with **In Progress**.

- [ ] **Step 4: Commit + open PR**

```bash
git add docs/PROGRESS.md
git commit -m "docs(progress): Plan 05b in progress"
git push -u origin plan-05b-whatsapp-cloud-send
gh pr create --title "Plan 05b: WhatsApp Cloud /send wiring + integration"
```
