# CLAUDE.md

Instructions for any AI agent (Claude Code, sub-agents, or pair-programming sessions) working in this repository. **Read this fully before taking any action.** Then read [`ARCHITECTURE.md`](./ARCHITECTURE.md) for the system design, and [`GLOSSARY.md`](./GLOSSARY.md) for shared terminology. If a package has its own `CLAUDE.md` or `AGENTS.md`, read that after this one — package-level files override repo-level ones when they conflict.

---

## What FaleCom is

FaleCom is an open-source omnichannel communication platform. A single Rails 8.1 app owns the full domain (contacts, conversations, messages, users, teams, flows, agent workspace). Around it sits a queue-first ingestion pipeline: managed AWS API Gateway + per-channel SQS queues + tiny Roda containers that translate provider-specific payloads into a single common ingestion format.

**Read `ARCHITECTURE.md` before doing architectural work.** That document is the source of truth. This file is about *how to work*, not *what to build*.

---

## The Dev Flow — DEFINE → PLAN → BUILD → VERIFY → DOCS → REVIEW → SHIP

Every non-trivial change follows these seven phases, in order. You cannot skip a phase. You can loop back from VERIFY or REVIEW to BUILD, but you always move forward from that point — never skip forward.

"Non-trivial" means anything that touches code behavior. Fixing a typo in a comment doesn't need the full flow. Adding a method, changing a query, adding a route, creating a migration — all non-trivial.

When in doubt, run the full flow. The overhead is cheap; the cost of skipping is a broken main branch.

### DEFINE

Write a spec for what will be built. A spec answers four questions:

1. **What problem are we solving?** One paragraph. If you can't state the problem, stop and ask the human.
2. **What is in scope?** Bullet list. Specific. Observable. "User can assign a conversation to a team" — not "improve assignment".
3. **What is out of scope?** Bullet list. Equally specific. This is where most specs earn their keep — the things we explicitly *won't* do in this change.
4. **What changes about the system?** Reference `ARCHITECTURE.md`. If this change contradicts the architecture, the architecture needs updating first — say so and stop.

Spec lives in the PR description or in `docs/specs/YYYY-MM-DD-short-name.md` for anything bigger than a single commit's worth of work.

**Brainstorm before writing.** The first draft of the spec is almost always wrong in interesting ways. Talk through edge cases out loud. Ask yourself: what would make this spec wrong? What did I assume that I shouldn't have?

You cannot move to PLAN until a human explicitly approves the spec.

### PLAN

Write the plan only after the spec is approved. A plan is a tests-first execution order.

Plans must include, at minimum:

1. **Files to touch** — list every file you expect to create or modify. If the list is wrong, your understanding of the code is wrong.
2. **Tests that will be written** — name each test. Test names are specifications. "`it rejects ingest when channel is not registered`" is a good test name; "`it tests the controller`" is not.
3. **Test types required** — unit tests are mandatory. If the change affects the dashboard UI, an end-to-end Playwright test is also mandatory. Integration tests are required when multiple services/containers interact.
4. **Migration order** — if migrations are involved, list them in execution order with rollback strategy for each.
5. **Order of operations** — which test first, which file first, what should be green before what. TDD is not optional.
6. **What could go wrong** — one paragraph. What's the most likely way this breaks? What's the least likely way?

Plans live in `docs/plans/NN-YYYY-MM-DD-short-name.md` or the PR body.

You cannot move to BUILD until the plan is reviewed. For small changes, review can be yourself reading your own plan after a short break. For anything larger, get a human.

### TRACKING (`docs/PROGRESS.md`)

`docs/PROGRESS.md` is the single live index of every spec and every plan and its current state. It is not optional — without it, in-flight work is invisible between sessions and specs/plans get duplicated or forgotten.

Update `docs/PROGRESS.md` at every phase boundary. Each entry carries a status from the set below; transitioning the entry is part of the phase, not a follow-up task:

- **Draft** — spec/plan file exists, no human approval yet
- **Approved** — approved by a human, ready for the next phase
- **Planned** — (spec-only) at least one plan has been written against this spec
- **In Progress** — build underway under at least one plan
- **Shipped** — merged to `main` (for a spec: all of its plans shipped)

Concrete update points:

- **DEFINE** — new spec file committed → add a row to the Specs table with status **Draft**. Spec approved by a human → move to **Approved**.
- **PLAN** — new plan file committed → add a row to the Plans table with status **Draft**, and flip the parent spec to **Planned**. Plan approved → **Approved**.
- **BUILD** — first commit of implementation work → plan status **In Progress**; parent spec **In Progress**.
- **SHIP** — PR merged to `main` → plan status **Shipped**. When every plan under a spec is **Shipped**, the spec itself becomes **Shipped**.

Each row links to the spec/plan file and, once shipped, to the merged PR. One line per entry; keep it short — this file is an index, not documentation.

### BUILD

Execute the plan using strict TDD:

1. **TDD First**: Write the test. Run it. Report the failure reason.
2. **Minimal Code**: Write the minimum code to pass.
3. **Verify**: Run the test. Run the related suite.
4. **Manual Proof**: Before finishing, perform the manual steps defined in the spec and report the UI behavior. Use `rake ingest:mock` to verify real-time updates.
5. **E2E Check**: If touching the pipeline, verify that a message goes from the channel container to the Rails dashboard.
6. **Commit**: Use Conventional Commits.

**Never skip work because files were already broken.** If you find broken code on the way to your goal, fix it. If the fix is large, stop, update the plan, surface the detour to the human, and proceed.

**Never use fixtures in end-to-end tests.** Playwright tests must drive real requests through the real API with real data. Seed data goes through the normal creation paths. If a creation path is too slow for tests, that's a signal to look at the creation path, not a signal to fake it.

**Use sub-agents for parallelizable tasks** — running test suites, scaffolding boilerplate files, searching for usages of a symbol across the monorepo. Don't use sub-agents for anything that requires continuity of judgment.

**Run the related test suite before moving on.** If you touched Rails dashboard code, run the full dashboard test suite, not just the single file you changed. Broken tests in adjacent areas are your responsibility to notice.

### VERIFY

Run the full test suite across the entire platform. All unit, integration, and end-to-end tests must pass.

- `bundle exec rspec` (unit/integration)
- `bin/rails test:system` (E2E UI tests)
- **Manual Smoke Test**: Run the application, perform the primary action in the browser, and verify Turbo Stream broadcasts and DB state.
- `bin/standardrb --fix` (linting)
- Migration round-trip check.

If anything fails, go back to BUILD. Do not explain away failures. Do not mark tests as pending. Fix them or revert the change.

### DOCUMENTATION UPDATE

- `README.md` at repo root — update if setup steps changed
- `ARCHITECTURE.md` — update if the architecture changed. If you changed the architecture without updating this file, you didn't change the architecture; you introduced drift.
- `GLOSSARY.md` — add any new terms. If you used a term in code that wasn't in the glossary, either add it or rename it to a term that is.
- `packages/*/AGENTS.md` — if an agent made a mistake in this package that was later corrected, record the mistake and the correction here so the next agent doesn't repeat it. This file is a lessons-learned log, not a style guide.
- Postman collection / API docs — update if any endpoint request/response shape changed. Out-of-date API docs are worse than missing ones.
- Migration notes — if the migration requires data backfill or downtime, document it in the PR body with operational steps.

### REVIEW

Open a pull request. Every PR must include:

1. **Link to the spec.**
2. **Link to the plan.**
3. **Summary of changes** — prose, not a file list. Describe what the system does now that it didn't do before.
4. **Manual testing guide** — numbered steps a human can follow to verify the change works. The end-to-end test you wrote is the basis for these steps; the test proves it works automatically, the manual guide lets a human confirm it feels right.
5. **Screenshots or recordings** — for any UI change. No exceptions.
6. **Risk assessment** — one paragraph. What is the blast radius if this goes wrong? Is the change reversible?

Reviewers are not responsible for understanding the change from the diff alone. The PR body is part of the deliverable.

### SHIP

On merge to `main`, GitHub Actions runs the full test suite: unit, integration, end-to-end. Deployment is triggered from a green main only.

If CI fails on main, the person who merged is responsible for rolling back or fixing forward within 30 minutes. No exceptions.

---

## Repository conventions

### Language and tooling

- **Ruby** — version pinned in `.ruby-version` (Ruby 4.0.2). Use `asdf` or `mise`, not `rbenv`, to match the team.
- **Dev environment** — the supported path is the devcontainer at `.devcontainer/devcontainer.json`. Opening the repo in VS Code / Cursor with the Dev Containers extension boots the full stack (Postgres, app, channel containers, dev-webhook) and attaches you into a workspace with Ruby, standardrb, node, aws-cli, and Terraform pre-installed. `postCreateCommand` runs `bin/setup` which installs deps and prepares the database. Contributors working outside a devcontainer can use `bin/setup` + `docker compose up` from the host, given the right Ruby installed via `mise`/`asdf`.
- **Rails 8.1** — the app package (`packages/app`).
- **Roda** — the channel container apps and the `dev-webhook` helper.
- **RSpec** — the test framework across all packages.
- **standardrb** — the linter. No Rubocop config overrides. If standardrb complains, fix the code.
- **Solid Queue, Solid Cable, Solid Cache** — the Rails 8 defaults. Do not introduce Redis, Sidekiq, or any other auxiliary infra unless the spec explicitly justifies it.
- **Postgres** — the only database. Do not add MongoDB, Redis, Elasticsearch, or anything else without a spec that explains why Postgres can't do the job.
- **ViewComponent + JR Components (Jetrockets UI)** — the component library. Components are copied into the repo (no gem dependency on JR).
- **Tailwind CSS 4** + **Vite** (via `vite_rails`) — the asset pipeline.
- **Hotwire (Turbo + Stimulus)** — the interactivity layer. No React, Vue, or Svelte in the dashboard. If a feature genuinely needs a SPA-style interaction (the visual flow builder is the one foreseen case), it gets an isolated island — not a gradual migration.

### Monorepo layout

```
falecom/
├── .devcontainer/           ← workspace environment (VS Code / Cursor)
├── packages/
│   ├── falecom_channel/     ← shared gem for channel containers
│   ├── channels/            ← one Roda app per channel type
│   │   ├── whatsapp-cloud/
│   │   ├── zapi/
│   │   └── ...
│   └── app/                 ← Rails 8.1 — domain + API + dashboard
├── infra/
│   ├── dev-webhook/         ← local dev API Gateway mock
│   ├── terraform/           ← AWS API Gateway + SQS + DLQ + IAM
│   ├── docker-compose.yml   ← dev runtime (workspace + services)
│   └── docker-compose.prod.yml   ← reference only, not the deploy manifest
├── docs/
│   ├── specs/
│   └── plans/
├── CLAUDE.md                ← this file
├── AGENTS.md                ← points to this file
├── ARCHITECTURE.md
├── GLOSSARY.md
└── README.md
```

Each `packages/*/` is independently buildable and testable. A PR that touches the Rails app should not require changes in a channel container, and vice versa — the `falecom_channel` gem is the only intentional shared surface between them.

### Naming

- **Files and directories** — `snake_case.rb`. Multi-word directories in `kebab-case` only when they're deploy units (`whatsapp-cloud`, `dev-webhook`). Everything inside follows Ruby conventions.
- **Classes and modules** — `CamelCase`. Namespaces mirror directory structure.
- **Methods** — `snake_case`. Predicates end with `?`. Destructive methods end with `!`. Don't overload these.
- **Database columns** — `snake_case`, singular for booleans (`active`, not `is_active`), full words (`updated_at`, not `upd`).
- **Test files** — `*_spec.rb`. Test descriptions are specifications, not descriptions of code.

### Events and audit log

Events are module-prefixed and past-tense: `conversations:created`, `messages:inbound`, `flows:handoff`, `contacts:merged`. The full catalogue lives in `ARCHITECTURE.md → Audit`.

**Audit-by-default is non-negotiable.** Every action that changes state of a Conversation, Contact, Channel, User, Team, Flow, or AutomationRule emits an `Event`. There are no exceptions and no "we'll add the event later" — the event is part of the feature.

### State changes happen in Services only

State mutations go through `app/services/**/*.rb`. Not controllers. Not jobs. Not views. The pattern:

- **Controller** — parses input, calls a service, renders response
- **Job** — loads context, calls a service, handles retry semantics
- **Service** — authorizes, validates, mutates, emits events
- **Model** — validates data, persists, exposes scopes and associations

If you are about to call `record.update!` from a controller or a view, stop. Write the service. The service is what gets tested, what emits the event, and what future API endpoints will reuse.

### Migrations

- One migration per concern. Don't combine a schema change with a data backfill — run the backfill in a separate migration or a rake task.
- Every migration must be reversible or explicitly marked irreversible with a comment explaining why.
- Long-running data migrations run as Solid Queue jobs, not in `rails db:migrate`. Migrations should be fast and safe to re-run on a hot instance.
- Never edit a migration that has been applied to any environment. Add a new one.

### Error handling

- Never swallow exceptions silently. Either handle them with a specific response or let them propagate to the global handler.
- Every rescued exception that isn't re-raised gets logged with structured context (account_id, conversation_id, external_id if available).
- Every background job has a failure path. Solid Queue's default retry + DLQ is the minimum. Jobs that touch external services must be idempotent.

### Secrets and credentials

- Nothing sensitive in the repo. Rails encrypted credentials for app secrets. Environment variables for infra coordinates.
- Channel credentials (WhatsApp access tokens, Z-API keys) live in the `channels.credentials` column, encrypted via ActiveRecord Encryption. Never in ENV.
- HMAC secrets for `/internal/ingest` and `/send` are environment variables, rotated via deploy, not via the database.

---

## Working with the Common Ingestion Payload

The Common Ingestion Payload (see `ARCHITECTURE.md`) is the single most important contract in the system. Every channel container produces it. Rails consumes it. Changes to this contract ripple across every container.

Rules:

1. **Required fields are required** — the schema (`FaleComChannel::Payload`) validates them. Never accept a payload that fails validation.
2. **Common fields first, metadata second** — if two providers both have a concept (e.g., "forwarded message"), it belongs in the common schema. If only one provider has it, it goes in `metadata` with a provider-prefixed key.
3. **`raw` is read-only for humans** — stored for audit and debugging. Never drive business logic from `raw`. If you find yourself reaching into `raw` in application code, the common schema is missing a field.
4. **Breaking changes to the payload are major version bumps** of the `falecom_channel` gem, and require updating every container in the same PR. CI enforces this.

---

## Working with channels

Adding a new channel is a predictable workflow:

1. Spec the provider's inbound and outbound shapes. Which fields map to common fields? Which go to `metadata`?
2. Add the provider's `channel_type` as a known value in the Rails app.
3. Create `packages/channels/{provider}/` using the existing `whatsapp-cloud` container as a template.
4. Write the `Parser` (provider → common payload), `SignatureVerifier`, and `Sender` (common outbound → provider API).
5. Add an SQS queue + API Gateway route in `infra/terraform`.
6. Add a seed `Channel` record in the Rails dev seeds so the new channel is exercised end-to-end in local dev.

Every one of those steps needs a test. No exceptions.

---

## What to do when stuck

- **The spec doesn't match the code.** Stop. The spec is wrong, the code is wrong, or both. Surface to the human. Don't paper over.
- **The test is hard to write.** The design is wrong. Don't make the test complicated; change the design so the test is simple.
- **You're three files deep and it's getting worse.** Revert. Go back to PLAN. The plan was wrong.
- **You want to add a gem.** Don't, unless the spec explicitly called for it. If it did, check if Rails 8 defaults already do the job. Most new gems are regret waiting to happen.
- **You're about to disable a test.** Don't. Fix the test or fix the code.
- **You're about to disable CI on merge.** Don't. Ever.

---

## What this file is not

- **Not a style guide.** Standardrb is the style guide.
- **Not the architecture.** `ARCHITECTURE.md` is the architecture.
- **Not a glossary.** `GLOSSARY.md` is the glossary.
- **Not an installation guide.** Setup steps, generator commands, and tooling recipes belong in specs (`docs/specs/`) and are executed during the BUILD phase. This file defines *constraints* ("use Postgres, not Redis"), not *instructions* ("run `rails new ...`").
- **Not complete.** When you discover a convention that's not documented, document it. When you find this file is wrong, fix it in the same PR as the change that revealed it.
