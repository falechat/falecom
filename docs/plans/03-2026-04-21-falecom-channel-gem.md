# Plan 03: `falecom_channel` Gem

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` to execute the parallel phases.
> **Spec:** [03 — `falecom_channel` Gem](../specs/03-falecom-channel-gem.md)
> **Date:** 2026-04-21
> **Status:** Draft — awaiting approval
> **Branch:** `spec-03-falecom-channel-gem`

**Goal:** Ship the shared `falecom_channel` gem at `packages/falecom_channel/`. Contains the Common Ingestion Payload schema (dry-struct/dry-validation), an abstract `QueueAdapter` with an SQS-backed implementation, a `Consumer` mixin, `IngestClient` + `DispatchClient` Faraday clients, a Roda `SendServer` base, a `HmacSigner`, and a structured `Logging` helper with correlation-id propagation. Gem is consumed by channel containers via path dependency; Rails does not depend on the gem yet (Spec 05 wires `DispatchClient` in).

**Architecture:** Standalone Ruby gem, no Rails dependency. Tests run under plain RSpec. SQS access via `aws-sdk-sqs`; dev environments point the SDK at LocalStack (added to `docker-compose.yml` only when Spec 04's first channel container lands — gem specs use `Aws::SQS::Client.new(stub_responses: true)` and need no live SQS).

**Tech Stack:** Ruby 4.0.2 (matches repo `.ruby-version`), RSpec, `standardrb`, `dry-struct`, `dry-validation`, `faraday`, `faraday-retry`, `aws-sdk-sqs`, `roda`, `rack-test` (dev), `webmock` (dev), `concurrent-ruby` (for the Consumer thread pool).

---

## Reconciliation notes (spec vs. architecture vs. decisions)

Open items resolved by human on 2026-04-21 (caveman-mode session):

1. **Queue backend.** SQS only, but `QueueAdapter` stays an abstract interface so a future backend can be added without changing consumer code. `FaleComChannel::QueueAdapter.build` returns an `SqsAdapter` today; `backend:` keyword accepted but only `:sqs` valid. Drops the Postgres `local` adapter and the `SELECT FOR UPDATE SKIP LOCKED` risk line. Dev uses LocalStack via `AWS_ENDPOINT_URL_SQS` — wired in Spec 04, not here.
2. **`outbound_echo` type.** Dropped from architecture. Three types remain: `inbound_message`, `outbound_status_update`, `outbound_message` (the last is dispatch-only, Rails → container). Plan E.3 removes the stale reference from `ARCHITECTURE.md:316`.
3. **`DispatchClient` location.** Stays in the gem. Different secret, different retry posture, separate class. Rails will `gem "falecom_channel", path: ...` in Spec 05 — not in this plan.
4. **`HmacSigner` addition.** New `FaleComChannel::HmacSigner` module (spec §2.8 slot that was blank). Both `IngestClient` and `DispatchClient` call `HmacSigner.sign`; `SendServer` calls `HmacSigner.verify!`. Centralizing prevents every channel container from hand-rolling HMAC code that must match Rails byte-for-byte. Secret + signature scheme exactly as `ARCHITECTURE.md:1349`.
5. **Consumer default concurrency.** Default `1`. Override via `concurrency ENV.fetch("CONCURRENCY", 1).to_i` in containers. Reason: a single long-poll thread is the safe baseline; ops can tune up per channel.

---

## Files to touch

All paths relative to repo root. Every command runs inside the `falecom-workspace-1` container via `docker exec falecom-workspace-1 <cmd>`.

### Create — gem scaffold

- `packages/falecom_channel/falecom_channel.gemspec`
- `packages/falecom_channel/Gemfile` (references gemspec)
- `packages/falecom_channel/.rspec`
- `packages/falecom_channel/Rakefile`
- `packages/falecom_channel/.standard.yml` (inherits root config)
- `packages/falecom_channel/lib/falecom_channel.rb` (top-level require)
- `packages/falecom_channel/lib/falecom_channel/version.rb` (`VERSION = "0.1.0"`)
- `packages/falecom_channel/spec/spec_helper.rb`

### Create — library

- `lib/falecom_channel/payload.rb` (dispatcher: `validate!`, `valid?`, `parse`)
- `lib/falecom_channel/payload/types.rb` (`dry-types` module)
- `lib/falecom_channel/payload/inbound_message.rb`
- `lib/falecom_channel/payload/outbound_status_update.rb`
- `lib/falecom_channel/payload/outbound_message.rb`
- `lib/falecom_channel/logging.rb` (`FaleComChannel.logger`, `with_correlation_id`, thread-local access)
- `lib/falecom_channel/hmac_signer.rb` (`sign`, `verify!`, `InvalidSignatureError`)
- `lib/falecom_channel/queue_adapter.rb` (factory + abstract interface)
- `lib/falecom_channel/queue_adapter/sqs_adapter.rb`
- `lib/falecom_channel/consumer.rb` (mixin, `start`, graceful shutdown)
- `lib/falecom_channel/ingest_client.rb` (Faraday + retry + HMAC + `IngestError`)
- `lib/falecom_channel/dispatch_client.rb` (Faraday no-retry + HMAC + `DispatchError`)
- `lib/falecom_channel/send_server.rb` (Roda base, HMAC verify, `/send` + `/health`)
- `lib/falecom_channel/errors.rb` (error hierarchy)

### Create — specs

- `spec/payload/inbound_message_spec.rb`
- `spec/payload/outbound_status_update_spec.rb`
- `spec/payload/outbound_message_spec.rb`
- `spec/payload_spec.rb` (dispatcher round-trip)
- `spec/logging_spec.rb`
- `spec/hmac_signer_spec.rb`
- `spec/queue_adapter_spec.rb` (factory + `SqsAdapter` via `stub_responses`)
- `spec/consumer_spec.rb` (multi-threaded smoke, graceful shutdown)
- `spec/ingest_client_spec.rb` (Faraday test adapter)
- `spec/dispatch_client_spec.rb` (Faraday test adapter)
- `spec/send_server_spec.rb` (`rack-test`)
- `spec/integration/pipeline_spec.rb` (Consumer → IngestClient → stubbed Rails, correlation-id + HMAC verified end-to-end)
- `spec/support/fixtures.rb` (canonical payload fixtures pulled from `ARCHITECTURE.md`)

### Create — docs

- `packages/falecom_channel/README.md` — consumer example from `ARCHITECTURE.md:465`, ENV reference (`SQS_QUEUE_NAME`, `FALECOM_API_URL`, `FALECOM_INGEST_HMAC_SECRET`, `FALECOM_DISPATCH_HMAC_SECRET`, `AWS_REGION`, `AWS_ENDPOINT_URL_SQS`), versioning policy.

### Modify

- `.github/workflows/ci.yml` — add `packages/falecom_channel` to test/lint matrix (mirrors `packages/app` entry).
- `ARCHITECTURE.md` — strike `outbound_echo` from line 316; rewrite § Queue Adapter block (line 1050) to describe the abstract adapter + `SqsAdapter` only, remove `SELECT FOR UPDATE SKIP LOCKED` reference.
- `docs/PROGRESS.md` — add Plan 03 row, flip Spec 03 to `Planned` → `In Progress` → `Shipped` at the appropriate phase boundaries.

---

## Test catalogue

Test names are specifications.

### `spec/payload/inbound_message_spec.rb`

- `it accepts the canonical ARCHITECTURE.md inbound_message example`
- `it rejects when channel.type is missing`
- `it rejects when channel.identifier is missing`
- `it rejects when contact.source_id is missing`
- `it rejects when message.external_id is missing`
- `it rejects when message.direction is not inbound or outbound`
- `it rejects when message.content_type is outside the allowed list`
- `it rejects when message.sent_at is missing`
- `it defaults attachments to [] when omitted`
- `it defaults metadata to {} when omitted`
- `it accepts optional contact fields (name, phone_number, email, avatar_url)`
- `it accepts reply_to_external_id`
- `it preserves raw verbatim when present`

### `spec/payload/outbound_status_update_spec.rb`

- `it accepts a valid delivered status update`
- `it rejects when external_id is missing`
- `it rejects when status is outside {sent, delivered, read, failed}`
- `it rejects when timestamp is missing`
- `it accepts optional error string`

### `spec/payload/outbound_message_spec.rb`

- `it accepts a valid outbound_message dispatch payload`
- `it rejects when message.internal_id is missing`
- `it rejects when contact.source_id is missing`
- `it defaults attachments to [] when omitted`
- `it accepts reply_to_external_id`

### `spec/payload_spec.rb`

- `FaleComChannel::Payload.validate!` dispatches to `InboundMessage` when `type == "inbound_message"`
- `FaleComChannel::Payload.validate!` dispatches to `OutboundStatusUpdate` when `type == "outbound_status_update"`
- `FaleComChannel::Payload.validate!` dispatches to `OutboundMessage` when `type == "outbound_message"`
- `FaleComChannel::Payload.validate!` raises `FaleComChannel::InvalidPayloadError` on unknown `type`
- `FaleComChannel::Payload.valid?` returns `true` for the canonical fixtures and `false` for mutated fixtures
- `FaleComChannel::Payload.parse` returns a typed struct with `Integer`/`String` accessors

### `spec/logging_spec.rb`

- `FaleComChannel.logger` emits one JSON line per call, to stdout
- `FaleComChannel::Logging.with_correlation_id(id) { ... }` sets thread-local; nested blocks restore on exit
- `FaleComChannel::Logging.current_correlation_id` returns `nil` outside a block
- logger output includes `correlation_id` automatically when inside `with_correlation_id`

### `spec/hmac_signer_spec.rb`

- `HmacSigner.sign(body, secret, timestamp:)` returns `"sha256=<hex>"` matching a hand-computed OpenSSL digest
- `HmacSigner.verify!(body, signature, timestamp, secret)` returns `true` on valid sig within tolerance
- `HmacSigner.verify!` raises `InvalidSignatureError` on tampered body
- `HmacSigner.verify!` raises `InvalidSignatureError` on tampered signature
- `HmacSigner.verify!` raises `InvalidSignatureError` when timestamp is older than `tolerance` (default 300s)
- `HmacSigner.verify!` raises `InvalidSignatureError` when timestamp is more than `tolerance` in the future (clock-skew protection)
- `HmacSigner.verify!` uses `OpenSSL.secure_compare` (constant-time)

### `spec/queue_adapter_spec.rb`

- `QueueAdapter.build(backend: :sqs, queue_name: "q")` returns a `SqsAdapter`
- `QueueAdapter.build` with unknown backend raises `ArgumentError`
- `SqsAdapter#consume` yields `(body, headers)` tuples from stubbed `ReceiveMessage`
- `SqsAdapter#ack(receipt_handle)` calls `DeleteMessage` with the handle
- `SqsAdapter#nack(receipt_handle)` calls `ChangeMessageVisibility` with `visibility_timeout: 0`
- `SqsAdapter#enqueue(payload)` calls `SendMessage` with the JSON-encoded payload (used by `dev-webhook` in Spec 04)
- `SqsAdapter` resolves `queue_url` from `queue_name` on first call and caches it
- `SqsAdapter` reads `AWS_ENDPOINT_URL_SQS` env var (LocalStack compatibility)

### `spec/consumer_spec.rb`

- `including FaleComChannel::Consumer` defines `queue_name` / `concurrency` class setters
- `#start` spins up `concurrency` threads, each invoking `#handle(body, headers)` for each received message
- successful `#handle` → adapter receives `ack(receipt_handle)`
- `#handle` raising `StandardError` → adapter receives `nack(receipt_handle)` and error is logged with correlation_id
- `SIGTERM` causes `#start` to stop pulling new messages, let in-flight messages complete, then return
- `SIGINT` behaves identically
- default `concurrency` is `1` when not set
- `#ingest_client` returns a memoized `FaleComChannel::IngestClient`
- each received message wraps `#handle` in `Logging.with_correlation_id(generated_uuid)`

### `spec/ingest_client_spec.rb`

- `IngestClient#post(payload)` POSTs JSON to `#{api_url}/internal/ingest`
- request includes `X-FaleCom-Signature`, `X-FaleCom-Timestamp`, `X-FaleCom-Correlation-Id`, `Content-Type: application/json`
- signature is `HmacSigner.sign(raw_body, FALECOM_INGEST_HMAC_SECRET, timestamp:)`
- returns parsed response body on 2xx
- retries on 5xx up to 3 times with exponential backoff (asserted via Faraday test adapter stub count)
- does NOT retry on 4xx
- raises `FaleComChannel::IngestError` after retries exhausted
- connect timeout 5s, read timeout 10s configured on the Faraday connection
- logs `event: "ingest_post"` with correlation_id, status code, duration

### `spec/dispatch_client_spec.rb`

- `DispatchClient#send_message(payload)` POSTs JSON to `#{container_url}/send`
- request is HMAC-signed with `FALECOM_DISPATCH_HMAC_SECRET` (separate from ingest secret)
- **no retries** on 5xx — single attempt (Solid Queue is the retrier)
- raises `FaleComChannel::DispatchError` on non-2xx
- returns parsed JSON response body on 2xx (e.g. `{ "external_id" => "wamid..." }`)
- connect timeout 5s, read timeout 30s (providers are slow)
- logs `event: "dispatch_post"` with correlation_id, status code, duration

### `spec/send_server_spec.rb`

- `GET /health` returns 200 `{"status":"ok"}`
- `POST /send` with valid HMAC + valid payload → calls `#handle_send(typed_payload)` and returns its result as JSON
- `POST /send` with missing `X-FaleCom-Signature` → 401
- `POST /send` with tampered body (signature mismatch) → 401
- `POST /send` with stale timestamp → 401
- `POST /send` with invalid payload (fails `Payload.validate!`) → 422 `{"error":"..."}`
- `#handle_send` raising → 500 `{"error":"..."}`, logged with correlation_id
- correlation_id pulled from `X-FaleCom-Correlation-Id` header if present, generated fresh otherwise

### `spec/integration/pipeline_spec.rb`

- Full inbound flow: stubbed SQS receives a WhatsApp Cloud-shaped canonical payload → Consumer pulls it → Consumer validates via `Payload.validate!` → IngestClient POSTs to a Faraday test stub representing Rails → stub asserts signature + correlation_id + body match → Consumer `ack`s the message.
- Failure flow: stub returns 500 thrice → IngestClient raises `IngestError` → Consumer `nack`s the message.

### Test types required

- **Unit:** every file above. Mandatory.
- **Integration:** `spec/integration/pipeline_spec.rb` exercises the full inbound code path in-process (stubbed SQS + stubbed HTTP). Mandatory.
- **E2E:** none in this plan — no channel container exists yet. Spec 04 carries the real end-to-end Playwright-ish test via `dev-webhook`.

---

## Order of operations

Strict TDD: test first, watch it fail, implement, watch it pass, commit. Parallelization starts in Wave 1 once Wave 0's scaffold is green.

### Wave 0 — Scaffold (sequential)

0.1. Create feature branch `spec-03-falecom-channel-gem` from `main`. Push. No code yet.

0.2. Gem scaffold: `falecom_channel.gemspec`, `Gemfile`, `.rspec`, `Rakefile`, `.standard.yml`, `lib/falecom_channel.rb` (just requires `version`), `lib/falecom_channel/version.rb`, `spec/spec_helper.rb`. Run `bundle install` inside the workspace container, `bundle exec rspec` (zero specs, green), `bundle exec standardrb`. Commit `chore: scaffold falecom_channel gem`.

0.3. Wire gem into CI: extend `.github/workflows/ci.yml` with a matrix entry that `cd packages/falecom_channel && bundle install && bundle exec standardrb && bundle exec rspec`. Push. Confirm CI green on empty suite. Commit `chore: add falecom_channel to CI matrix`.

0.4. `spec/support/fixtures.rb` with canonical fixtures copied verbatim from `ARCHITECTURE.md § Common Ingestion Payload`. Commit `chore: add canonical payload fixtures`.

### Wave 1 — Foundation (parallel, 2 subagents)

Both cards depend only on Wave 0. Dispatch in parallel.

- **1A — Payload schemas.** Owns: `lib/falecom_channel/payload.rb`, `payload/types.rb`, `payload/inbound_message.rb`, `payload/outbound_status_update.rb`, `payload/outbound_message.rb`, and the four payload specs. TDD: write `inbound_message_spec.rb` against the canonical fixture first, watch it fail, implement the dry-struct, move on.
- **1B — Logging + HmacSigner.** Owns: `lib/falecom_channel/logging.rb`, `lib/falecom_channel/hmac_signer.rb`, `lib/falecom_channel/errors.rb`, and the two specs. No external dependencies — pure stdlib + OpenSSL.

### Wave 2 — Infrastructure modules (parallel, 3 subagents)

All three depend on Wave 1 merging first. Dispatch simultaneously after Wave 1.

- **2A — QueueAdapter + Consumer.** Owns: `lib/falecom_channel/queue_adapter.rb`, `queue_adapter/sqs_adapter.rb`, `lib/falecom_channel/consumer.rb`, and the two specs. Uses `Aws::SQS::Client.new(stub_responses: true)` for unit tests, `Concurrent::ThreadPoolExecutor` for the worker pool. Graceful shutdown via a shared `Concurrent::AtomicBoolean` flag flipped in the signal trap.
- **2B — IngestClient + DispatchClient.** Owns: `lib/falecom_channel/ingest_client.rb`, `lib/falecom_channel/dispatch_client.rb`, and the two specs. Both use `Faraday.new` with the Faraday test adapter in specs. `faraday-retry` middleware configured on `IngestClient` only. Shared HMAC header construction extracted to a small `Internal::SignedRequest` module within `ingest_client.rb` (not public API).
- **2C — SendServer.** Owns: `lib/falecom_channel/send_server.rb` and its spec. Roda app with `json` + `json_parser` plugins. HMAC verify middleware added as `before` hook in the route block. Uses `rack-test` in specs.

### Wave 3 — Integration + polish (sequential, single agent, main session)

3.1. Integration spec (`spec/integration/pipeline_spec.rb`) wiring all modules together. Runs against stubbed SQS + stubbed HTTP — no live network.

3.2. `packages/falecom_channel/README.md`: consumer example + ENV reference + versioning policy.

3.3. Documentation drift fix (DOCS phase): remove `outbound_echo` from `ARCHITECTURE.md:316`; rewrite `ARCHITECTURE.md § Queue Adapter` (line 1050 block) to describe the abstract `QueueAdapter` + `SqsAdapter` only, dropping the Postgres `local` adapter and the `SELECT FOR UPDATE SKIP LOCKED` line. Cross-check spec §6 risks — the `SELECT FOR UPDATE` bullet there also goes.

3.4. Update `docs/PROGRESS.md`: Plan 03 → `In Progress` at start of Wave 0, → `Shipped` on PR merge. Spec 03 follows.

3.5. Full suite: inside workspace container, `cd packages/falecom_channel && bundle exec rspec && bundle exec standardrb --fix`. Then from repo root, `docker exec falecom-workspace-1 bash -c "cd packages/app && bundle exec rspec && bin/standardrb"` to confirm no regressions in the Rails app (should be none — gem is standalone).

3.6. Open PR. CI must be green before merging.

---

## Subagent dispatch specification

Every Wave-1 and Wave-2 card dispatches a fresh `general-purpose` subagent (`model: sonnet`, low-effort guidance in the prompt) running in the background.

Each brief must include, verbatim:

1. **Card number + scope** (e.g. `2A — QueueAdapter + Consumer`).
2. **Exact files** the card owns (copy from "Files to touch" above).
3. **Exact spec test names** from the catalogue above.
4. **TDD order**: write the spec → `docker exec falecom-workspace-1 bash -c "cd packages/falecom_channel && bundle exec rspec spec/<file>"` → confirm failure → implement → re-run → green.
5. **Pre-commit verification rule (MANDATORY, from memory):** before every commit, subagent must run the **full** `docker exec falecom-workspace-1 bash -c "cd packages/falecom_channel && bundle exec rspec"` — not just its own file. Adjacent regressions are the subagent's responsibility.
6. **Lint rule:** `docker exec falecom-workspace-1 bash -c "cd packages/falecom_channel && bundle exec standardrb --fix"` before every commit.
7. **Hard rules:** no gems outside the list in "Tech Stack". No touching `packages/app`. No touching other cards' files. No Rails-isms (`ActiveSupport::Concern`, etc.) — gem is standalone Ruby. Use `require_relative` within the gem.
8. **Docker rule (from memory):** every `bundle`, `rspec`, `standardrb`, `bin/*` invocation goes through `docker exec falecom-workspace-1 ...`. Host has no Ruby.
9. **Commit convention:** Conventional Commits. `feat(falecom_channel): add Payload::InboundMessage` / `test(falecom_channel): add HmacSigner specs` / etc.
10. **On completion:** return commit SHAs + the green RSpec output for the spec files the card owns.

Main session reviews each subagent's diff before dispatching the next wave. Drift → main session fixes, does not re-dispatch.

---

## What could go wrong

**Most likely:** dry-struct/dry-validation DSL trips up the subagent on the nested attribute blocks (`attribute :channel do ... end`). Schema validation errors may be confusing until the `dry-types` module is pinned correctly. Mitigation: Card 1A starts from the canonical fixture in `spec/support/fixtures.rb` and works outside-in — if the fixture passes, the schema is right.

**Second most likely:** HMAC signature drift between gem and Rails. `HmacSigner.sign` computes `sha256=<hex>` over the *raw* request body. If `IngestClient` serializes the payload to JSON *after* signing (or if keys reorder), the signature won't match what Rails verifies in Spec 04. Mitigation: `IngestClient` serializes once into a `String`, signs that string, and passes it as the body — never re-serializes. Spec `ingest_client_spec.rb` asserts body-as-sent matches body-as-signed.

**Least likely but highest blast radius:** Consumer threading bugs — especially around graceful shutdown. A signal trap that doesn't flip the flag atomically, or a `ThreadPoolExecutor#shutdown` call that doesn't wait for in-flight tasks, can lose messages. Mitigation: `consumer_spec.rb` has an explicit "SIGTERM lets in-flight handle complete" test that races a long-running `#handle` against a simulated signal.

---

## Rollback strategy

Gem is additive — lives entirely under `packages/falecom_channel/`. Nothing else in the repo imports it yet (Rails depends on it only from Spec 05). If the PR must revert, `git revert` of the merge commit removes the whole gem with zero downstream cleanup. CI matrix entry removal is a one-line revert in `.github/workflows/ci.yml`. `ARCHITECTURE.md` drift fixes are independently safe to keep (they just correct prior docs).

---

## Acceptance (from Spec 03)

All 9 acceptance criteria from Spec 03 §5 must pass at end of Wave 3. CI green on PR is the final gate.
