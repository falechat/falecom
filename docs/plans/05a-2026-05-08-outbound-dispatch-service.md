# Plan 05a: Outbound Dispatch — Service + Job (Rails)

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> **Spec:** [05 — Outbound Dispatch](../specs/05-outbound-dispatch.md)
> **Date:** 2026-05-08
> **Status:** Draft — awaiting approval
> **Branch:** `plan-05a-outbound-dispatch-service`

**Goal:** Ship the Rails-only outbound rails: `Dispatch::Outbound` service + `SendMessageJob` (Solid Queue) + outbound payload builder + dedicated `outbound` queue. After this plan, callers (future controller, future flow engine, current console) can call `Dispatch::Outbound.call(...)` and a job will pick the message up, build a Common outbound payload, POST it via `FaleComChannel::DispatchClient` to a configurable container URL, mark the message `sent` (or `failed` on error), and emit `messages:outbound` / `messages:sent` / `messages:failed` events. No dashboard, no real container — the container target is mocked at the Faraday adapter layer in specs. Plan 05b wires the real WhatsApp Cloud `/send` endpoint; Plan 05c adds the reply form.

**Architecture:** `Dispatch::Outbound` is a thin orchestrator: it calls `Messages::Create` with `direction: "outbound"`, `status: "pending"`, then enqueues `SendMessageJob` inside `ActiveRecord::Base.after_all_transactions_committed` to avoid the "worker picks up before row visible" race (Spec 05 §2.2). `SendMessageJob` is idempotent (early-return when `status == "sent"`), retries on `Faraday::Error` via `retry_on`, and on terminal failure marks the message `failed` and emits `messages:failed`. Container URL resolution is `ENV.fetch("CHANNEL_#{channel_type.upcase}_URL")` — one env per channel type. HMAC secret comes from `ENV["FALECOM_DISPATCH_HMAC_SECRET"]` (matches the gem's `DispatchClient` contract).

**Tech Stack:** Ruby 4.0.2, Rails 8.1.3, Solid Queue, RSpec 7.1, `standardrb`, `falecom_channel` gem (already a path dep — provides `DispatchClient` + `HmacSigner`). Faraday stubs for HTTP-layer specs. No new gems.

---

## Files to touch

All paths relative to repo root. Every command runs inside the `falecom-workspace-1` container via `docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && …"`.

### Create — services / jobs

- `packages/app/app/services/dispatch/outbound.rb`
- `packages/app/app/services/dispatch/outbound_payload_builder.rb`
- `packages/app/app/services/dispatch/container_url_resolver.rb`
- `packages/app/app/jobs/send_message_job.rb`

### Create — specs

- `packages/app/spec/services/dispatch/outbound_spec.rb`
- `packages/app/spec/services/dispatch/outbound_payload_builder_spec.rb`
- `packages/app/spec/services/dispatch/container_url_resolver_spec.rb`
- `packages/app/spec/jobs/send_message_job_spec.rb`
- `packages/app/spec/support/dispatch_client_stub.rb` — Faraday-level stub helper reused across specs

### Modify

- `packages/app/config/queue.yml` — register `outbound` queue with dedicated worker pool (Spec 05 §2.7).
- `packages/app/config/application.rb` (or `config/environments/*.rb`) — set `config.active_job.queue_adapter = :solid_queue` already done in Spec 01; verify only.
- `packages/app/.env.development` (and `.env.test`) — add `CHANNEL_WHATSAPP_CLOUD_URL` placeholder + `FALECOM_DISPATCH_HMAC_SECRET=dev-dispatch-secret` if not present.

---

## Order of operations (TDD wave)

1. **Queue config** — add `outbound` queue to `config/queue.yml`, restart Solid Queue worker, verify.
2. **`Dispatch::ContainerUrlResolver`** — pure function, no deps. Test first.
3. **`Dispatch::OutboundPayloadBuilder`** — takes a `Message`, returns a hash matching `FaleComChannel::Payload` outbound shape. Test against payload schema.
4. **`SendMessageJob`** — happy path, idempotency guard, retry-on-Faraday, terminal failure path. Faraday stubbed.
5. **`Dispatch::Outbound`** — service wraps `Messages::Create` + `after_all_transactions_committed { SendMessageJob.perform_later(...) }`. Test enqueue timing.
6. **Regression sweep** — full `packages/app` rspec + standardrb.

Each task ends with a commit. Conventional Commits prefixes (`feat`, `fix`, `test`, `chore`).

---

## What could go wrong

**Most likely:** `after_all_transactions_committed` fires only inside an open transaction. If a future caller invokes `Dispatch::Outbound.call(...)` from a context with no surrounding transaction (e.g., a rake task), the block runs synchronously — fine for correctness, but worth covering explicitly with a spec that calls outside any transaction. Test in Task 5.

**Least likely:** the `outbound` queue and `default` queue compete for the same worker pool and outbound starves under load. Spec 05 §2.7 calls for separate threads. Solid Queue's `queue.yml` supports this; verify in Task 1 with a `bin/jobs` boot check.

---

## Task 1: Queue config

**Files:**
- Modify: `packages/app/config/queue.yml`

- [ ] **Step 1: Edit `queue.yml` to add a dedicated `outbound` worker pool**

```yaml
default: &default
  dispatchers:
    - polling_interval: 1
      batch_size: 500
  workers:
    - queues: ["default", "low"]
      threads: 5
      processes: <%= ENV.fetch("JOB_CONCURRENCY", 1) %>
      polling_interval: 0.1
    - queues: ["outbound"]
      threads: 3
      processes: <%= ENV.fetch("JOB_CONCURRENCY", 1) %>
      polling_interval: 0.1

development:
  <<: *default

test:
  <<: *default

production:
  <<: *default
```

- [ ] **Step 2: Boot Solid Queue and confirm both worker pools register**

Run: `docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && bundle exec bin/jobs --help"` to confirm config parses, then `bin/jobs run --queue outbound` briefly to confirm the queue is recognized (Ctrl-C after 2s).
Expected: no parse errors. Log line shows worker for `outbound` queue.

- [ ] **Step 3: Commit**

```bash
git add packages/app/config/queue.yml
git commit -m "chore(queue): add dedicated outbound worker pool for Plan 05a"
```

---

## Task 2: `Dispatch::ContainerUrlResolver`

**Files:**
- Create: `packages/app/app/services/dispatch/container_url_resolver.rb`
- Test: `packages/app/spec/services/dispatch/container_url_resolver_spec.rb`

- [ ] **Step 1: Write the failing spec**

```ruby
require "rails_helper"

RSpec.describe Dispatch::ContainerUrlResolver do
  it "resolves CHANNEL_WHATSAPP_CLOUD_URL for whatsapp_cloud" do
    ClimateControl.modify("CHANNEL_WHATSAPP_CLOUD_URL" => "http://wa:9292") do
      expect(described_class.call("whatsapp_cloud")).to eq("http://wa:9292")
    end
  end

  it "raises KeyError when env var is missing" do
    ClimateControl.modify("CHANNEL_WHATSAPP_CLOUD_URL" => nil) do
      expect { described_class.call("whatsapp_cloud") }.to raise_error(KeyError)
    end
  end

  it "uppercases and underscores the channel_type for env lookup" do
    ClimateControl.modify("CHANNEL_Z_API_URL" => "http://z:9293") do
      expect(described_class.call("z_api")).to eq("http://z:9293")
    end
  end
end
```

- [ ] **Step 2: Run, verify it fails (no constant defined)**

Run: `bundle exec rspec spec/services/dispatch/container_url_resolver_spec.rb`
Expected: FAIL — `NameError: uninitialized constant Dispatch::ContainerUrlResolver`.

- [ ] **Step 3: Implement**

```ruby
module Dispatch
  class ContainerUrlResolver
    def self.call(channel_type)
      ENV.fetch("CHANNEL_#{channel_type.upcase}_URL")
    end
  end
end
```

- [ ] **Step 4: Run, verify pass**

Run: `bundle exec rspec spec/services/dispatch/container_url_resolver_spec.rb`
Expected: 3 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add packages/app/app/services/dispatch/container_url_resolver.rb \
        packages/app/spec/services/dispatch/container_url_resolver_spec.rb
git commit -m "feat(dispatch): add ContainerUrlResolver for per-channel container URL lookup"
```

---

## Task 3: `Dispatch::OutboundPayloadBuilder`

**Files:**
- Create: `packages/app/app/services/dispatch/outbound_payload_builder.rb`
- Test: `packages/app/spec/services/dispatch/outbound_payload_builder_spec.rb`

- [ ] **Step 1: Write the failing spec**

```ruby
require "rails_helper"

RSpec.describe Dispatch::OutboundPayloadBuilder do
  let(:channel) { create(:channel, channel_type: "whatsapp_cloud", identifier: "wa-1", credentials: {access_token: "tok", phone_number_id: "pn-1"}) }
  let(:contact_channel) { create(:contact_channel, channel: channel, source_id: "55119...") }
  let(:conversation) { create(:conversation, channel: channel, contact_channel: contact_channel) }
  let(:message) do
    create(:message,
      channel: channel,
      conversation: conversation,
      direction: "outbound",
      status: "pending",
      content: "hi",
      content_type: "text",
      reply_to_external_id: "wamid.123",
      metadata: {"foo" => "bar"})
  end

  it "builds an outbound_message payload with channel/contact/message blocks" do
    payload = described_class.call(message)

    expect(payload[:type]).to eq("outbound_message")
    expect(payload[:channel]).to eq(type: "whatsapp_cloud", identifier: "wa-1")
    expect(payload[:contact]).to eq(source_id: "55119...")
    expect(payload[:message]).to include(
      internal_id: message.id,
      content: "hi",
      content_type: "text",
      attachments: [],
      reply_to_external_id: "wamid.123"
    )
  end

  it "merges decrypted channel.credentials into metadata.channel_credentials" do
    payload = described_class.call(message)

    expect(payload[:metadata]).to include("foo" => "bar")
    expect(payload[:metadata]["channel_credentials"]).to eq("access_token" => "tok", "phone_number_id" => "pn-1")
  end

  it "passes FaleComChannel::Payload.validate! for the outbound shape" do
    payload = described_class.call(message)
    expect { FaleComChannel::Payload.validate!(payload.deep_stringify_keys) }.not_to raise_error
  end
end
```

- [ ] **Step 2: Run, verify it fails**

Run: `bundle exec rspec spec/services/dispatch/outbound_payload_builder_spec.rb`
Expected: FAIL — uninitialized constant.

- [ ] **Step 3: Implement**

```ruby
module Dispatch
  class OutboundPayloadBuilder
    def self.call(message)
      channel = message.channel
      conversation = message.conversation
      contact_channel = conversation.contact_channel

      {
        type: "outbound_message",
        channel: {
          type: channel.channel_type,
          identifier: channel.identifier
        },
        contact: {
          source_id: contact_channel.source_id
        },
        message: {
          internal_id: message.id,
          content: message.content,
          content_type: message.content_type,
          attachments: [],
          reply_to_external_id: message.reply_to_external_id
        },
        metadata: message.metadata.to_h.merge(
          "channel_credentials" => channel.credentials.to_h.deep_stringify_keys
        )
      }
    end
  end
end
```

- [ ] **Step 4: Run, verify pass**

Run: `bundle exec rspec spec/services/dispatch/outbound_payload_builder_spec.rb`
Expected: 3 examples, 0 failures. If the third example fails because `FaleComChannel::Payload` does not yet declare an `outbound_message` schema, stop and check the gem — Spec 03 should have added it. If missing, add it in `packages/falecom_channel/lib/falecom_channel/payload.rb` and bump the gem patch version. Commit the gem change in a separate commit before continuing.

- [ ] **Step 5: Commit**

```bash
git add packages/app/app/services/dispatch/outbound_payload_builder.rb \
        packages/app/spec/services/dispatch/outbound_payload_builder_spec.rb
git commit -m "feat(dispatch): build common outbound payload from Message"
```

---

## Task 4: `SendMessageJob`

**Files:**
- Create: `packages/app/app/jobs/send_message_job.rb`
- Test: `packages/app/spec/jobs/send_message_job_spec.rb`
- Create: `packages/app/spec/support/dispatch_client_stub.rb`

- [ ] **Step 1: Write the support helper**

```ruby
# packages/app/spec/support/dispatch_client_stub.rb
module DispatchClientStub
  def stub_dispatch_client(response: {"external_id" => "ext-1"}, raise: nil)
    fake = instance_double(FaleComChannel::DispatchClient)
    if raise
      allow(fake).to receive(:send_message).and_raise(raise)
    else
      allow(fake).to receive(:send_message).and_return(response)
    end
    allow(FaleComChannel::DispatchClient).to receive(:new).and_return(fake)
    fake
  end
end

RSpec.configure { |c| c.include DispatchClientStub }
```

- [ ] **Step 2: Write the failing job spec**

```ruby
require "rails_helper"

RSpec.describe SendMessageJob do
  let(:channel) { create(:channel, channel_type: "whatsapp_cloud", identifier: "wa-1") }
  let(:conversation) { create(:conversation, channel: channel) }
  let(:message) { create(:message, channel: channel, conversation: conversation, direction: "outbound", status: "pending", content: "hi", content_type: "text") }

  before { ClimateControl.modify("CHANNEL_WHATSAPP_CLOUD_URL" => "http://wa:9292", "FALECOM_DISPATCH_HMAC_SECRET" => "s") }

  it "POSTs via DispatchClient and marks message sent" do
    fake = stub_dispatch_client(response: {"external_id" => "ext-9"})

    described_class.perform_now(message.id)

    expect(fake).to have_received(:send_message).with(hash_including(type: "outbound_message"))
    expect(message.reload).to have_attributes(status: "sent", external_id: "ext-9")
  end

  it "emits messages:sent on success" do
    stub_dispatch_client
    expect { described_class.perform_now(message.id) }
      .to change { Event.where(name: "messages:sent", subject: message).count }.by(1)
  end

  it "is idempotent for already-sent messages" do
    message.update!(status: "sent", external_id: "ext-prior")
    fake = stub_dispatch_client
    described_class.perform_now(message.id)
    expect(fake).not_to have_received(:send_message)
  end

  it "discards on RecordNotFound" do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end

  it "raises Faraday::Error so Solid Queue retries" do
    stub_dispatch_client(raise: Faraday::ConnectionFailed.new("boom"))
    expect { described_class.perform_now(message.id) }.to raise_error(Faraday::Error)
    expect(message.reload.status).to eq("pending")
  end

  it "marks message failed on terminal non-Faraday error" do
    stub_dispatch_client(raise: ArgumentError.new("malformed"))
    expect { described_class.perform_now(message.id) }.not_to raise_error
    expect(message.reload).to have_attributes(status: "failed", error: "malformed")
    expect(Event.where(name: "messages:failed", subject: message)).to exist
  end
end
```

- [ ] **Step 3: Run, verify all six fail (job not defined)**

Run: `bundle exec rspec spec/jobs/send_message_job_spec.rb`
Expected: FAIL — `NameError: uninitialized constant SendMessageJob`.

- [ ] **Step 4: Implement the job**

```ruby
class SendMessageJob < ApplicationJob
  queue_as :outbound

  retry_on Faraday::Error, wait: :polynomially_longer, attempts: 5
  discard_on ActiveRecord::RecordNotFound

  def perform(message_id)
    message = Message.find(message_id)
    return if message.status == "sent"

    payload = Dispatch::OutboundPayloadBuilder.call(message)
    container_url = Dispatch::ContainerUrlResolver.call(message.channel.channel_type)

    response = FaleComChannel::DispatchClient
      .new(container_url: container_url, secret: ENV.fetch("FALECOM_DISPATCH_HMAC_SECRET"))
      .send_message(payload)

    message.update!(external_id: response.fetch("external_id"), status: "sent")
    Events::Emit.call(name: "messages:sent", subject: message, actor: :system)
    broadcast_status(message)
  rescue Faraday::Error
    raise
  rescue => e
    message.update!(status: "failed", error: e.message)
    Events::Emit.call(name: "messages:failed", subject: message, actor: :system)
    broadcast_status(message)
  end

  private

  def broadcast_status(message)
    # Plan 05d wires the actual Turbo Stream target. For 05a we keep this as a
    # no-op placeholder so the job stays decoupled from the dashboard.
    nil
  end
end
```

- [ ] **Step 5: Run, verify all six pass**

Run: `bundle exec rspec spec/jobs/send_message_job_spec.rb`
Expected: 6 examples, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add packages/app/app/jobs/send_message_job.rb \
        packages/app/spec/jobs/send_message_job_spec.rb \
        packages/app/spec/support/dispatch_client_stub.rb
git commit -m "feat(jobs): add SendMessageJob with retry, idempotency, and failure handling"
```

---

## Task 5: `Dispatch::Outbound`

**Files:**
- Create: `packages/app/app/services/dispatch/outbound.rb`
- Test: `packages/app/spec/services/dispatch/outbound_spec.rb`

- [ ] **Step 1: Write the failing spec**

```ruby
require "rails_helper"

RSpec.describe Dispatch::Outbound do
  let(:user) { create(:user) }
  let(:channel) { create(:channel, channel_type: "whatsapp_cloud") }
  let(:conversation) { create(:conversation, channel: channel) }

  it "creates an outbound Message with status: pending" do
    expect {
      described_class.call(conversation: conversation, content: "hi", actor: user)
    }.to change(Message, :count).by(1)

    msg = Message.last
    expect(msg).to have_attributes(direction: "outbound", status: "pending", content: "hi", sender: user)
  end

  it "enqueues SendMessageJob after the transaction commits" do
    expect {
      ActiveRecord::Base.transaction do
        described_class.call(conversation: conversation, content: "hi", actor: user)
        expect(enqueued_jobs_for(SendMessageJob)).to be_empty   # not yet — txn open
      end
    }.to have_enqueued_job(SendMessageJob)
  end

  it "emits messages:outbound" do
    expect {
      described_class.call(conversation: conversation, content: "hi", actor: user)
    }.to change { Event.where(name: "messages:outbound").count }.by(1)
  end

  it "passes reply_to_external_id through" do
    described_class.call(conversation: conversation, content: "hi", actor: user, reply_to_external_id: "wamid.x")
    expect(Message.last.reply_to_external_id).to eq("wamid.x")
  end

  it "works outside an active transaction (synchronous enqueue)" do
    expect {
      described_class.call(conversation: conversation, content: "hi", actor: user)
    }.to have_enqueued_job(SendMessageJob)
  end
end
```

(`enqueued_jobs_for` is a one-line spec helper: `def enqueued_jobs_for(klass) = ActiveJob::Base.queue_adapter.enqueued_jobs.select { _1[:job] == klass }`. Add to `spec/support/active_job_helpers.rb` if not already present.)

- [ ] **Step 2: Run, verify all five fail**

Run: `bundle exec rspec spec/services/dispatch/outbound_spec.rb`
Expected: FAIL — uninitialized constant.

- [ ] **Step 3: Implement**

```ruby
module Dispatch
  class Outbound
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

      ActiveRecord::Base.after_all_transactions_committed do
        SendMessageJob.perform_later(message.id)
      end

      message
    end
  end
end
```

- [ ] **Step 4: Run, verify all five pass**

Run: `bundle exec rspec spec/services/dispatch/outbound_spec.rb`
Expected: 5 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add packages/app/app/services/dispatch/outbound.rb \
        packages/app/spec/services/dispatch/outbound_spec.rb
git commit -m "feat(dispatch): add Dispatch::Outbound orchestrator service"
```

---

## Task 6: Regression sweep + PROGRESS.md

- [ ] **Step 1: Full app rspec**

Run: `docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && bundle exec rspec"`
Expected: all green. If anything in `messages/` or `ingestion/` specs broke from queue config or sender column changes, fix forward — do not skip.

- [ ] **Step 2: standardrb**

Run: `docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && bin/standardrb --fix"`
Expected: no offenses.

- [ ] **Step 3: Update `docs/PROGRESS.md`** — flip Spec 05 row to **In Progress** and add the 05a Plan row with status **In Progress**.

- [ ] **Step 4: Commit + open PR**

```bash
git add docs/PROGRESS.md
git commit -m "docs(progress): Plan 05a in progress"
git push -u origin plan-05a-outbound-dispatch-service
gh pr create --title "Plan 05a: Outbound dispatch service + SendMessageJob" \
             --body-file docs/plans/05a-2026-05-08-outbound-dispatch-service.md
```

After merge, flip the row to **Shipped** in a follow-up doc commit (matches PR #5 / 04 pattern).
