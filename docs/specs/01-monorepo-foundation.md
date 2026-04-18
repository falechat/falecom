# Spec: Monorepo Foundation & Dev Environment

> **Phase:** 1 (Foundation)
> **Execution Order:** 1 of 7 — execute first, no dependencies
> **Date:** 2026-04-17
> **Status:** Draft — awaiting approval

---

## 1. What problem are we solving?

FaleCom has a complete architecture document and development workflow, but no code exists yet. Before any feature can be built, we need:

- A reproducible dev environment that any contributor can spin up with a single action (devcontainer open or `bin/setup` + `docker compose up`).
- The Rails 8.1 application scaffold with the Solid trio (Queue, Cable, Cache) configured so that future specs can immediately write services, jobs, and real-time features.
- The frontend asset pipeline (Vite + Tailwind CSS 4 + JR Components + ViewComponent) wired and working so UI work can start without a separate "tooling day."
- A CI pipeline that enforces code quality from the first commit.
- The monorepo directory layout matching `ARCHITECTURE.md` so every future spec can reference paths that already exist.

Without this foundation, every subsequent spec would need to deal with setup concerns, leading to conflated PRs and inconsistent bootstrapping.

---

## 2. What is in scope?

This spec is split into two sub-phases that can be executed sequentially in the same PR or as two separate PRs.

### Phase 1A — Backend Scaffold

- [ ] **Ruby version pinning** — `.ruby-version` file at repo root (Ruby 4.0.2).
- [ ] **Root-level Gemfile** — for shared dev tooling only (`standardrb`). Not for application gems.
- [ ] **`.devcontainer/devcontainer.json`** — workspace definition referencing `infra/docker-compose.yml`, installing features (Node LTS, aws-cli, GitHub CLI, Terraform), configuring VS Code extensions (Ruby LSP, Tailwind, Prettier, Terraform), and running `bin/setup` via `postCreateCommand`. Matches the structure documented in `ARCHITECTURE.md § Local development`.
- [ ] **`.devcontainer/workspace.Dockerfile`** (or equivalent) — image with Ruby + standardrb + postgresql-client.
- [ ] **`infra/docker-compose.yml`** — services: `workspace`, `postgres` (16-alpine). Placeholders (commented out) for `app`, `app-jobs`, `dev-webhook`, and channel containers — services will be uncommented as their specs are executed.
- [ ] **`infra/docker-compose.prod.yml`** — reference-only file with a header comment explaining it is not a deploy manifest.
- [ ] **Rails 8.1 app scaffold** at `packages/app`:
  - Generated with `rails new packages/app --database=postgresql --devcontainer --skip-asset-pipeline --skip-javascript` (we will replace the asset pipeline with Vite in Phase 1B).
  - Rails-generated devcontainer files at `packages/app/.devcontainer` are **deleted** after generation — we use the monorepo-level devcontainer only.
  - `database.yml` configured to connect to `postgres://falecom:falecom@postgres:5432/falecom_development` (matching the compose service).
- [ ] **Solid Queue** installed (`bin/rails solid_queue:install`), configured in `config/queue.yml`.
- [ ] **Solid Cable** installed (`bin/rails solid_cable:install`), configured in `config/cable.yml`.
- [ ] **Solid Cache** installed (`bin/rails solid_cache:install`), configured in `config/cache.yml` (or via `config.cache_store`).
- [ ] **Rails 8 authentication generator** run (`bin/rails generate authentication`), producing `sessions` and `users` table skeleton.
- [ ] **RSpec** installed as the test framework (`rspec-rails`). Default Minitest removed.
- [ ] **`bin/setup`** script at repo root — idempotent:
  1. `cd packages/app && bundle install`
  2. `bin/rails db:prepare`
  3. Seed dev account (placeholder — real seeds come in the Core Domain spec)
- [ ] **CI pipeline** — `.github/workflows/ci.yml`:
  - Triggered on every PR and push to `main`.
  - Steps: checkout → setup Ruby → `bundle exec standardrb` (root) → `cd packages/app && bundle exec rspec`.
- [ ] **Empty directory placeholders** (with `.gitkeep`):
  - `packages/falecom_channel/`
  - `packages/channels/`
  - `infra/dev-webhook/`
  - `infra/terraform/`
  - `docs/specs/` (this file goes here)
  - `docs/plans/`

### Phase 1B — UI Foundation

- [ ] **`vite_rails`** installed in `packages/app` (`bundle add vite_rails && bundle exec vite install`).
- [ ] **Vite config** (`config/vite.json`, `vite.config.ts`) verified working — `bin/dev` starts both Rails and Vite dev server.
- [ ] **TailwindCSS 4** installed via Vite, per the JR Components getting-started guide.
- [ ] **`view_component`** gem installed (`bundle add view_component`).
- [ ] **JR Components** copied into `app/components/ui/` following the [Jetrockets getting-started guide](https://ui.jetrockets.com/ui/getting_started). Components are owned in the repo — no gem dependency.
- [ ] **JR form builder** configured as the app's default form builder.
- [ ] **Stimulus** controllers from JR wired into Vite entry points.
- [ ] **Base layout** (`app/views/layouts/application.html.erb`):
  - JR Navbar component (placeholder links).
  - JR Sidebar component (placeholder links).
  - Dark mode support via Tailwind's `dark:` utilities.
  - Responsive shell.
- [ ] **Login page** — uses JR form fields, styled with the design system. Functional authentication against the Rails 8 auth generator output.
- [ ] **Dashboard shell** — empty authenticated page with the layout. Placeholder "Welcome" content.
- [ ] **`Procfile.dev`** — `bin/dev` starts Rails server + Vite dev server (HMR).

---

## 3. What is out of scope?

- **Database migrations for domain models** (accounts, teams, channels, conversations, messages, events, flows). Those belong in a separate "Core Domain Models" spec.
- **`falecom_channel` gem** implementation. A separate spec covers this.
- **Channel containers** (whatsapp-cloud, zapi, etc.). Separate specs.
- **`dev-webhook`** local gateway mock. Separate spec.
- **Terraform / AWS infra**. Separate spec.
- **Business logic of any kind** — no services, no jobs, no real seeds beyond a single dev user.
- **Playwright / system tests** — no UI features to test yet.
- **Production deployment configuration** — Kamal, ECS, Fly, etc. are roadmap items.

---

## 4. What changes about the system?

This is the **first commit** — there is no existing system. After this spec is executed:

- The monorepo layout documented in `ARCHITECTURE.md` physically exists.
- A developer can open the repo in VS Code/Cursor, wait for the devcontainer to build, and immediately run `bin/dev` to see a styled login page.
- CI enforces `standardrb` and `rspec` on every PR from day one.
- The Rails app is configured with the full Solid trio (Queue, Cable, Cache) backed by Postgres — no Redis, no external dependencies.
- The UI pipeline (Vite + Tailwind 4 + JR Components + ViewComponent) is production-ready, not bolted on later.

No contradictions with the architecture. This spec **implements** the foundation described in `ARCHITECTURE.md § Build Order → Phase 1`.

---

## 5. Acceptance criteria

### Phase 1A
1. `docker compose up workspace postgres` succeeds — workspace container starts with Ruby available.
2. Inside the workspace container, `cd /workspaces/falecom && bin/setup` completes without errors.
3. `cd packages/app && bin/rails db:migrate:status` shows Solid Queue + Solid Cable + Solid Cache + auth migrations applied.
4. `cd packages/app && bundle exec rspec` runs with zero failures (even if zero test files exist initially — the framework must load cleanly).
5. `bundle exec standardrb` passes at root level.
6. GitHub Actions CI runs and passes on a PR.

### Phase 1B
7. `cd packages/app && bin/dev` starts Rails + Vite. Navigating to `http://localhost:3000` shows the login page with JR-styled form fields.
8. Logging in with the seeded dev user shows the dashboard shell with Navbar + Sidebar.
9. Tailwind utilities work in views. Dark mode toggle (if present in JR) functions.
10. `bin/rails test` and `bundle exec rspec` continue to pass.
11. Hot Module Replacement works — editing a CSS file or Stimulus controller reflects immediately in the browser without full reload.

---

## 6. Risks

- **JR Components compatibility** — JR targets a specific Tailwind 4 + Vite setup. If their getting-started guide assumes a different Rails version or asset pipeline, we may need to adapt. Mitigation: follow the guide step-by-step; if it diverges, document the delta in `packages/app/AGENTS.md`.
- **Rails 8.1 vs 8.0** — Rails 8.1 may not be released at execution time. If only 8.0 is available, use 8.0 and note the version in `.ruby-version` and `Gemfile`. The architecture differences are minimal.
- **Devcontainer build time** — first build downloads images and installs gems. Could be slow. Mitigation: use Docker layer caching in CI; document expected first-build time in README.

---

## 7. Decided Architecture (Previously Open Questions)

1. **Ruby version** — Decided: Pin to **4.0.2**.
2. **Tailwind CSS** — Decided: Use **4.0.2** (latest stable).
3. **JR Components version** — Decided: Add a `packages/app/app/components/ui/VERSION` file noting the source URL and date of the copy-pasted components for traceability.
4. **Procfile.dev** — Decided: Use **`foreman`** as the default process manager via `bin/dev`. The `Procfile.dev` will be standard-compliant for developers preferring `overmind`.
