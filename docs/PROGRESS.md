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
| 02 | [Core Domain Models & Audit Logging](./specs/02-core-domain-models.md)                  | Draft    | —                      | Awaiting human approval before plan.                                                            |
| 03 | [`falecom_channel` Gem](./specs/03-falecom-channel-gem.md)                              | Draft    | —                      | Can run in parallel with Spec 02 once both are approved.                                        |
| 04 | [Ingestion Pipeline](./specs/04-ingestion-pipeline.md)                                  | Draft    | —                      | Depends on 02 + 03.                                                                             |
| 05 | [Outbound Dispatch](./specs/05-outbound-dispatch.md)                                    | Draft    | —                      | Depends on 02 + 03.                                                                             |
| 06 | [Assignment, Transfer & Agent Workspace](./specs/06-assignment-transfer-workspace.md)   | Draft    | —                      | Depends on 04 + 05.                                                                             |
| 07 | [Flow Engine](./specs/07-flow-engine.md)                                                | Draft    | —                      | Depends on 04 + 06.                                                                             |

## Plans

| #   | Plan                                                                                     | Spec | Status   | PR                                                          | Shipped    |
|-----|------------------------------------------------------------------------------------------|------|----------|-------------------------------------------------------------|------------|
| 01a | [Phase 1A — Backend Scaffold](./plans/01-2026-04-18-phase-1a-backend-scaffold.md)        | 01   | Shipped  | [#1](https://github.com/falechat/falecom/pull/1) (e3bbac7)  | 2026-04-18 |
| 01b | [Phase 1B — UI Foundation](./plans/01-2026-04-18-phase-1b-ui-foundation.md)              | 01   | Shipped  | [#2](https://github.com/falechat/falecom/pull/2) (50dd2d7)  | 2026-04-18 |

## Recently shipped

- **2026-04-18** — Spec 01 fully shipped via PRs #1 and #2. Repo now has Rails 8.1.3 + Solid Queue/Cable/Cache on Postgres, Rails 8 authentication, RSpec as the test framework, standardrb, Vite + Tailwind CSS 4 + ViewComponent + JR Components, a devcontainer-based dev environment, and a GitHub Actions CI pipeline that runs `standardrb` + `rspec` on every PR.

## Up next

- **Spec 02 — Core Domain Models & Audit Logging.** Needs human approval, then a plan (or set of plans) before build starts. Unblocks Specs 04, 05, 06, 07.
- **Spec 03 — `falecom_channel` Gem.** Independent of Spec 02; can be approved and planned in parallel.
