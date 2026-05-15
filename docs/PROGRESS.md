# Build Progress

Live index of every spec under [`docs/specs/`](./specs/) and every plan under [`docs/plans/`](./plans/), with current status. Update this file at every DEFINE → PLAN → BUILD → VERIFY → DOCS → REVIEW → SHIP transition so in-flight work is visible across sessions.

See [`CLAUDE.md § TRACKING`](../CLAUDE.md) for the full set of update rules.

## Status legend

- **Draft** — file exists, no human approval yet
- **Approved** — approved by a human, ready for the next phase
- **Planned** — (spec-only) at least one plan written against this spec
- **In Progress** — build underway under at least one plan
- **Shipped** — merged to `main` (for a spec: all of its plans shipped)

## Specs

| #  | Spec                                                                                    | Status   | Plans                  | Notes                                                                                           |
|----|-----------------------------------------------------------------------------------------|----------|------------------------|-------------------------------------------------------------------------------------------------|
| 01 | [Monorepo Foundation & Dev Environment](./specs/01-monorepo-foundation.md)              | Shipped  | 01a, 01b               | Foundation in place: Rails 8.1.3 at `packages/app`, Solid trio, RSpec, Vite + Tailwind 4 + JR.  |
| 02 | [Core Domain Models & Audit Logging](./specs/02-core-domain-models.md)                  | Shipped  | 02                     | Shipped 2026-04-21 via PR #3. All 10 core domain models + Events::Emit + Current.user + idempotent seeds in place. |
| 03 | [`falecom_channel` Gem](./specs/03-falecom-channel-gem.md)                              | Shipped  | 03                     | Shipped 2026-04-21 via PR #4. Gem provides Payload schemas, SqsAdapter, Consumer, HMAC clients, SendServer, Logging. |
| 04 | [Ingestion Pipeline](./specs/04-ingestion-pipeline.md)                                  | Shipped  | 04a, 04b               | Shipped 2026-04-22 via PR #5. Rails ingest + whatsapp-cloud container + dev-webhook + LocalStack SQS, full e2e green. |
| 05 | [Outbound Dispatch](./specs/05-outbound-dispatch.md)                                    | Shipped  | 05a, 05b, 05c, 05d     | Shipped 2026-05-08 across 4 plans (service/job, container send, reply form, status display). |
| 06 | [Assignment, Transfer & Agent Workspace](./specs/06-assignment-transfer-workspace.md)   | Shipped  | 06a, 06b, 06c, 06d, 06e, 06f | Shipped 2026-05-15 across six plans (authz/auto-assign, transfer, workspace, timeline, admin, realtime). |
| 07 | [Flow Engine](./specs/07-flow-engine.md)                                                | Planned  | 07a, 07b, 07c, 07d     | Spec sliced into four plans (migrations/models, engine services, ingestion integration, dashboard). |

## Plans

| #   | Plan                                                                                     | Spec | Status   | PR                                                          | Shipped    |
|-----|------------------------------------------------------------------------------------------|------|----------|-------------------------------------------------------------|------------|
| 01a | [Phase 1A — Backend Scaffold](./plans/01-2026-04-18-phase-1a-backend-scaffold.md)        | 01   | Shipped  | [#1](https://github.com/falechat/falecom/pull/1) (e3bbac7)  | 2026-04-18 |
| 01b | [Phase 1B — UI Foundation](./plans/01-2026-04-18-phase-1b-ui-foundation.md)              | 01   | Shipped  | [#2](https://github.com/falechat/falecom/pull/2) (50dd2d7)  | 2026-04-18 |
| 02  | [Core Domain Models & Audit Logging](./plans/02-2026-04-21-core-domain-models.md)        | 02   | Shipped  | [#3](https://github.com/falechat/falecom/pull/3) (7adbfde)  | 2026-04-21 |
| 03  | [`falecom_channel` Gem](./plans/03-2026-04-21-falecom-channel-gem.md)                    | 03   | Shipped  | [#4](https://github.com/falechat/falecom/pull/4) (1e7532f)  | 2026-04-21 |
| 04a | [Phase 4A — Ingestion Rails](./plans/04a-2026-04-22-ingestion-pipeline-rails.md) | 04   | Shipped  | [#5](https://github.com/falechat/falecom/pull/5) (9d630bf)  | 2026-04-22 |
| 04b | [Phase 4B — Ingestion Container + Infra](./plans/04b-2026-04-22-ingestion-pipeline-container.md) | 04   | Shipped  | [#5](https://github.com/falechat/falecom/pull/5) (9d630bf)  | 2026-04-22 |
| 05a | [Outbound Dispatch — Service + Job](./plans/05a-2026-05-08-outbound-dispatch-service.md) | 05   | Shipped  | [#7](https://github.com/falechat/falecom/pull/7) (b103b27)  | 2026-05-08 |
| 05b | [WhatsApp Cloud /send Wiring](./plans/05b-2026-05-08-whatsapp-cloud-send.md)             | 05   | Shipped  | [#8](https://github.com/falechat/falecom/pull/8) (1fafd8d)  | 2026-05-08 |
| 05c | [Reply Form Dashboard](./plans/05c-2026-05-08-reply-form-dashboard.md)                   | 05   | Shipped  | direct-to-main (4bde678)                                    | 2026-05-08 |
| 05d | [Status Display + Flow](./plans/05d-2026-05-08-status-display-flow.md)                   | 05   | Shipped  | direct-to-main (46c1cb7)                                    | 2026-05-08 |
| 06a | [Authorization + Auto-Assign + Availability](./plans/06a-2026-05-11-authz-autoassign-availability.md) | 06 | Shipped | [#11](https://github.com/falechat/falecom/pull/11) (4d062dd) | 2026-05-15 |
| 06b | [Transfer + Resolve](./plans/06b-2026-05-11-transfer-resolve.md)                         | 06   | Shipped  | [#12](https://github.com/falechat/falecom/pull/12) (c61d4c7) | 2026-05-15 |
| 06c | [Workspace views + 3-pane layout](./plans/06c-2026-05-11-workspace-views.md)             | 06   | Shipped  | [#13](https://github.com/falechat/falecom/pull/13) (452efcf) | 2026-05-15 |
| 06d | [Conversation timeline + content-type rendering](./plans/06d-2026-05-11-conversation-timeline.md) | 06 | Shipped | [#14](https://github.com/falechat/falecom/pull/14) (bdf64fa) | 2026-05-15 |
| 06e | [Admin UI + Contact management](./plans/06e-2026-05-11-admin-and-contact-mgmt.md)        | 06   | Shipped  | [#15](https://github.com/falechat/falecom/pull/15) (8286a0a) | 2026-05-15 |
| 06f | [Real-time scoping (Solid Cable)](./plans/06f-2026-05-11-realtime-scoping.md)            | 06   | Shipped  | [#16](https://github.com/falechat/falecom/pull/16) (3eb3486) | 2026-05-15 |
| 07a | [Flow migrations + models](./plans/07a-2026-05-15-flow-migrations-models.md)             | 07   | Draft    | —                                                           | —          |
| 07b | [Flow engine services](./plans/07b-2026-05-15-flow-engine-services.md)                   | 07   | Draft    | —                                                           | —          |
| 07c | [Flow ingestion integration + auto-assign depth](./plans/07c-2026-05-15-flow-ingestion-integration.md) | 07 | Draft | — | — |
| 07d | [Flow management dashboard](./plans/07d-2026-05-15-flow-management-dashboard.md)         | 07   | Draft    | —                                                           | —          |

## Recently shipped

- **2026-05-15** — Spec 06 fully shipped across six plans. Agent workspace now has the full assignment + transfer + resolve + real-time stack. 06a (PR #11) introduced `ConversationPolicy`, `Assignments::AutoAssign` (round-robin + capacity strategies, advisory-locked) + `AutoAssignJob`, and the `User#availability` column. 06b (PR #12) added `Assignments::Transfer` and `Conversations::Resolve` with audit events. 06c (PR #13) shipped the 3-pane workspace layout + filtered conversation lists (Mine/Queue/All) + sidebar. 06d (PR #14) delivered the `TimelineMessageComponent` (text/image/audio/video/document/location/contact_card partials) + system message component + status checkmark indicators. 06e (PR #15) rounded out admin CRUDs (channels, teams, users) + contact management. 06f (PR #16, merge `3eb3486`) wired the real-time layer: a single `Conversations::Broadcasts` module fans out to `conversation:<id>`, `conversations:channel:<cid>`, and `conversations:user:<uid>` streams; a `ConversationStreamGate` PORO + Turbo monkey-patch enforces per-user subscription authorization; the dashboard layout subscribes to the personal stream + one channel stream per team-attended channel. Suite finishes at 285 examples, 0 failures, 1 pending (Playwright placeholder).
- **2026-05-08** — Spec 05 fully shipped across 4 plans + a stacked dev-tooling PR. Outbound dispatch now flows agent → `Dispatch::Outbound` → `SendMessageJob` (Solid Queue, retry on 5xx/network) → `FaleComChannel::DispatchClient` → `channel-whatsapp-cloud` (Puma, /send) → `WhatsappCloud::Sender` → Meta v21 `/messages`. Status webhooks return through the inbound pipeline and update checkmarks live via `Ingestion::ProcessStatusUpdate` + Turbo Stream broadcasts. Plans 05a (PR #7), 05b (PR #8), 05c + 05d (direct to main). Bonus PR #9 added the meta-stub provider simulator (signed inbound + status webhooks driven from a tiny HTML form on `:4001`) so the inbound pipeline is exercisable end-to-end without a real Meta account. Gem hardening: `RetryableDispatchError < DispatchError`, `SendServer.error_status_for` hook, dev-webhook forwards provider auth headers as SQS message attributes, dev-webhook Dockerfile now COPYs `Gemfile.lock`. App suite: 171 RSpec examples + 6 ViewComponent specs + 4 request specs; full repo total 320 examples, 0 failures.
- **2026-04-22** — Spec 04 fully shipped via PR #5 (merge commit `9d630bf`). Plans 04a + 04b landed together: Rails `Internal::IngestController` with HMAC verification + Channel registration lookup, `Ingestion::ProcessMessage` + `Contacts::Resolve` + `Conversations::ResolveOrCreate` + `Messages::Create` services, first channel container `packages/channels/whatsapp-cloud` (Parser + SignatureVerifier + Sender + SendServer), `infra/dev-webhook`, and LocalStack SQS in `docker-compose.yml`. End-to-end pipeline (webhook → dev-webhook → SQS → container → /internal/ingest → DB → Turbo Stream) green via real LocalStack integration spec.
- **2026-04-21** — Spec 03 fully shipped via PR #4 (merge commit `1e7532f`). `packages/falecom_channel` gem now provides Common Ingestion Payload schemas (dry-struct), `QueueAdapter::SqsAdapter`, `Consumer` mixin with graceful shutdown, `IngestClient` (retry 5xx) + `DispatchClient` (no retry), `SendServer` Roda base, `HmacSigner`, and structured `Logging` with correlation-id propagation. 118 RSpec examples green. Architecture drift fixed in the same PR (`outbound_echo` dropped, Queue Adapter section rewritten SQS-only).
- **2026-04-21** — Spec 02 fully shipped via PR #3 (merge commit `7adbfde`). Repo now has the full core domain (User/Team/TeamMember/Channel/ChannelTeam/Contact/ContactChannel/Conversation/Message/AutomationRule/Event) with encrypted `Channel#credentials`, the `Events::Emit` audit service, the `Current.user` thread-local, Active Storage, and an idempotent dev seed dataset. 99 RSpec examples green in CI.
- **2026-04-18** — Spec 01 fully shipped via PRs #1 and #2. Repo now has Rails 8.1.3 + Solid Queue/Cable/Cache on Postgres, Rails 8 authentication, RSpec as the test framework, standardrb, Vite + Tailwind CSS 4 + ViewComponent + JR Components, a devcontainer-based dev environment, and a GitHub Actions CI pipeline that runs `standardrb` + `rspec` on every PR.

## Up next

- **Spec 07 — Flow Engine** (`docs/specs/07-flow-engine.md`, still Draft). Depends on 04 + 06 (both now Shipped).
- **Deploy-readiness follow-up:** real ActiveRecord Encryption keys must be committed to `config/credentials.yml.enc` before the first prod/staging deploy that exercises `Channel#credentials`. Test + development envs currently use static non-secret keys in `config/environments/*.rb`.
