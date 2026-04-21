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
| 03 | [`falecom_channel` Gem](./specs/03-falecom-channel-gem.md)                              | In Progress | 03                  | Build on branch `spec-03-falecom-channel-gem` — awaiting PR + merge.                            |
| 04 | [Ingestion Pipeline](./specs/04-ingestion-pipeline.md)                                  | Draft    | —                      | Depends on 02 + 03.                                                                             |
| 05 | [Outbound Dispatch](./specs/05-outbound-dispatch.md)                                    | Draft    | —                      | Depends on 02 + 03.                                                                             |
| 06 | [Assignment, Transfer & Agent Workspace](./specs/06-assignment-transfer-workspace.md)   | Draft    | —                      | Depends on 04 + 05.                                                                             |
| 07 | [Flow Engine](./specs/07-flow-engine.md)                                                | Draft    | —                      | Depends on 04 + 06.                                                                             |

## Plans

| #   | Plan                                                                                     | Spec | Status   | PR                                                          | Shipped    |
|-----|------------------------------------------------------------------------------------------|------|----------|-------------------------------------------------------------|------------|
| 01a | [Phase 1A — Backend Scaffold](./plans/01-2026-04-18-phase-1a-backend-scaffold.md)        | 01   | Shipped  | [#1](https://github.com/falechat/falecom/pull/1) (e3bbac7)  | 2026-04-18 |
| 01b | [Phase 1B — UI Foundation](./plans/01-2026-04-18-phase-1b-ui-foundation.md)              | 01   | Shipped  | [#2](https://github.com/falechat/falecom/pull/2) (50dd2d7)  | 2026-04-18 |
| 02  | [Core Domain Models & Audit Logging](./plans/02-2026-04-21-core-domain-models.md)        | 02   | Shipped  | [#3](https://github.com/falechat/falecom/pull/3) (7adbfde)  | 2026-04-21 |
| 03  | [`falecom_channel` Gem](./plans/03-2026-04-21-falecom-channel-gem.md)                    | 03   | In Progress | —                                                        | —          |

## Recently shipped

- **2026-04-21** — Spec 02 fully shipped via PR #3 (merge commit `7adbfde`). Repo now has the full core domain (User/Team/TeamMember/Channel/ChannelTeam/Contact/ContactChannel/Conversation/Message/AutomationRule/Event) with encrypted `Channel#credentials`, the `Events::Emit` audit service, the `Current.user` thread-local, Active Storage, and an idempotent dev seed dataset. 99 RSpec examples green in CI.
- **2026-04-18** — Spec 01 fully shipped via PRs #1 and #2. Repo now has Rails 8.1.3 + Solid Queue/Cable/Cache on Postgres, Rails 8 authentication, RSpec as the test framework, standardrb, Vite + Tailwind CSS 4 + ViewComponent + JR Components, a devcontainer-based dev environment, and a GitHub Actions CI pipeline that runs `standardrb` + `rspec` on every PR.

## Up next

- **Plan 03 — `falecom_channel` Gem.** Approved 2026-04-21. Build in progress on branch `spec-03-falecom-channel-gem` via subagent-driven-development playbook. Unblocks Spec 04 (Ingestion) and Spec 05 (Outbound Dispatch).
- **Deploy-readiness follow-up:** real ActiveRecord Encryption keys must be committed to `config/credentials.yml.enc` before the first prod/staging deploy that exercises `Channel#credentials`. Test + development envs currently use static non-secret keys in `config/environments/*.rb`.
