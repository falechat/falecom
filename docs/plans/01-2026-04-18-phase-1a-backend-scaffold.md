# Phase 1A: Backend Scaffold Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Spec:** [`docs/specs/01-monorepo-foundation.md`](../specs/01-monorepo-foundation.md) — Phase 1A only.

**Goal:** Bootstrap the FaleCom monorepo with a devcontainer-based dev environment, a Rails 8.1.3 app scaffold in `packages/app`, the Solid trio (Queue + Cable + Cache) on Postgres, Rails 8 authentication, RSpec, and a GitHub Actions CI pipeline that enforces `standardrb` + RSpec from day one.

**Architecture:** Host-side file authoring, container-side execution. A `workspace` Docker service (Ruby 4.0.2 + standardrb + Node LTS + postgresql-client) mounts the repo root as a volume; a `postgres:16-alpine` service provides the database. All Ruby / Rails / test commands execute inside `workspace` via `docker compose exec`; generated files land on the host through the volume mount. Claude Code writes files with host-side tools (`Write` / `Edit`), never from inside the container.

**Tech Stack:** Ruby 4.0.2, Rails 8.1.3, Postgres 16, Solid Queue, Solid Cable, Solid Cache, rspec-rails 7.x, standard (standardrb) ~> 1.50, Docker Compose, GitHub Actions.

**Executing model:** Sonnet 4.6 with low thinking — plan is prescriptive; every command has an exact expected output so the executor can detect divergence without reasoning.

**Prerequisites:**
- Docker Desktop (or equivalent) running on host.
- Git configured with `user.name` and `user.email`.
- Repo root is `/Users/cooper/dev/falecom` (adjust absolute paths below if running elsewhere).
- Working tree clean on `main` (the only existing content is `docs/`, `ARCHITECTURE.md`, `CLAUDE.md`, `GLOSSARY.md`, `README.md`).
- No `packages/`, `infra/`, or `.devcontainer/` directories exist yet.

**Conventions inside this plan:**
- `REPO` means the absolute host path `/Users/cooper/dev/falecom`.
- A `Run (host):` prefix means run on the host shell from `REPO`.
- A `Run (workspace):` prefix means run inside the workspace container: `docker compose -f infra/docker-compose.yml exec workspace bash -lc '<cmd>'`.
- Every file content block is the **exact** file body to write. Do not edit Rails-generated files except where a task explicitly tells you to.

---

## File structure produced by this plan

```
falecom/
├── .devcontainer/
│   ├── devcontainer.json
│   └── workspace.Dockerfile
├── .github/
│   └── workflows/
│       └── ci.yml
├── .gitignore                          ← augmented
├── .ruby-version                       ← new (4.0.2)
├── .standard.yml                       ← new
├── Gemfile                             ← root, dev tooling only
├── Gemfile.lock                        ← generated
├── bin/
│   └── setup                           ← root bootstrap
├── docs/
│   └── plans/                          ← this file + .gitkeep removed once content lives here
├── infra/
│   ├── docker-compose.yml
│   ├── docker-compose.prod.yml         ← reference only
│   ├── dev-webhook/.gitkeep
│   └── terraform/.gitkeep
└── packages/
    ├── app/                            ← Rails 8.1.3 scaffold
    │   ├── Gemfile                     ← modified (rspec-rails, no rubocop-omakase)
    │   ├── config/database.yml         ← pointed at the `postgres` service
    │   ├── spec/
    │   │   ├── rails_helper.rb
    │   │   ├── spec_helper.rb
    │   │   └── system_boot_spec.rb     ← the only spec in Phase 1A
    │   ├── app/models/{user,session,current}.rb   ← from auth generator
    │   ├── db/migrate/*                ← auth + solid_queue + solid_cable + solid_cache
    │   └── ... (full Rails tree)
    ├── channels/.gitkeep
    └── falecom_channel/.gitkeep
```

---

## Task 1: Pre-flight check

**Files:** none modified — a safety gate so later tasks don't accidentally overwrite uncommitted work.

- [ ] **Step 1: Confirm clean working tree on `main`**

Run (host): `cd /Users/cooper/dev/falecom && git status --porcelain && git rev-parse --abbrev-ref HEAD`

Expected: no output from `git status --porcelain` (clean tree), and `git rev-parse` prints `main`.

If the tree is dirty or the branch is not `main`, STOP and surface to the human.

- [ ] **Step 2: Confirm Docker is running**

Run (host): `docker version --format '{{.Server.Version}}'`

Expected: a version number like `27.x` or similar. If this errors with "Cannot connect to the Docker daemon", STOP and ask the human to start Docker.

- [ ] **Step 3: Confirm the Ruby 4.0.2-slim image tag exists on Docker Hub**

Run (host): `docker pull ruby:4.0.2-slim`

Expected: the image pulls (or is already present). If the tag does not exist on Docker Hub, STOP — the Dockerfile below pins this tag and will otherwise fail at build time.

- [ ] **Step 4: Create a working branch**

Run (host):
```bash
cd /Users/cooper/dev/falecom
git checkout -b phase-1a-backend-scaffold
```

Expected: `Switched to a new branch 'phase-1a-backend-scaffold'`.

---

## Task 2: Ruby version pin + root Gemfile + `.standard.yml`

**Files:**
- Create: `/Users/cooper/dev/falecom/.ruby-version`
- Create: `/Users/cooper/dev/falecom/Gemfile`
- Create: `/Users/cooper/dev/falecom/.standard.yml`

- [ ] **Step 1: Write `.ruby-version`**

Write `/Users/cooper/dev/falecom/.ruby-version` with content:

```
4.0.2
```

- [ ] **Step 2: Write root `Gemfile`**

Write `/Users/cooper/dev/falecom/Gemfile` with content:

```ruby
# Shared dev tooling only. Application gems live in packages/*/Gemfile.
# This Gemfile's sole purpose is to provide a single standardrb version
# used by CI to lint the whole monorepo.

source "https://rubygems.org"

ruby file: ".ruby-version"

gem "standard", "~> 1.50"
```

- [ ] **Step 3: Write `.standard.yml`**

Write `/Users/cooper/dev/falecom/.standard.yml` with content:

```yaml
ruby_version: 4.0.2
format: progress
# Rails 8.1 scaffold ships with style that standardrb accepts after
# `standardrb --fix`. We lint the whole monorepo from root.
```

- [ ] **Step 4: Verify files exist**

Run (host): `ls -la /Users/cooper/dev/falecom/.ruby-version /Users/cooper/dev/falecom/Gemfile /Users/cooper/dev/falecom/.standard.yml`

Expected: all three listed with non-zero size.

---

## Task 3: Root `.gitignore`

**Files:** Create: `/Users/cooper/dev/falecom/.gitignore`

- [ ] **Step 1: Write `.gitignore`**

Write `/Users/cooper/dev/falecom/.gitignore` with content:

```gitignore
# Ruby / Bundler
.bundle/
vendor/bundle/
*.gem

# Rails (app-level ignores live in packages/app/.gitignore too;
# these are safety nets at root)
log/*.log
tmp/
storage/
.env
.env.*
!.env.example

# Node / Vite (for Phase 1B)
node_modules/
public/vite-*
public/vite/
.vite/

# OS / editor
.DS_Store
Thumbs.db
.idea/
.vscode/*
!.vscode/extensions.json
!.vscode/settings.json.example

# Docker
infra/**/data/
.docker/
```

- [ ] **Step 2: Verify**

Run (host): `wc -l /Users/cooper/dev/falecom/.gitignore`

Expected: at least 20 lines.

---

## Task 4: Directory placeholders

**Files:**
- Create: `/Users/cooper/dev/falecom/packages/falecom_channel/.gitkeep`
- Create: `/Users/cooper/dev/falecom/packages/channels/.gitkeep`
- Create: `/Users/cooper/dev/falecom/infra/dev-webhook/.gitkeep`
- Create: `/Users/cooper/dev/falecom/infra/terraform/.gitkeep`

- [ ] **Step 1: Create each `.gitkeep`**

Use the `Write` tool four times, one per file, each with empty content (a zero-byte file).

- [ ] **Step 2: Verify**

Run (host):
```bash
ls /Users/cooper/dev/falecom/packages/falecom_channel/.gitkeep \
   /Users/cooper/dev/falecom/packages/channels/.gitkeep \
   /Users/cooper/dev/falecom/infra/dev-webhook/.gitkeep \
   /Users/cooper/dev/falecom/infra/terraform/.gitkeep
```

Expected: all four listed.

(Note: `docs/plans/` already contains this plan file — no `.gitkeep` needed there.)

---

## Task 5: Devcontainer configuration

**Files:**
- Create: `/Users/cooper/dev/falecom/.devcontainer/devcontainer.json`
- Create: `/Users/cooper/dev/falecom/.devcontainer/workspace.Dockerfile`

- [ ] **Step 1: Write `.devcontainer/devcontainer.json`**

Content:

```json
{
  "name": "falecom",
  "dockerComposeFile": "../infra/docker-compose.yml",
  "service": "workspace",
  "workspaceFolder": "/workspaces/falecom",
  "features": {
    "ghcr.io/devcontainers/features/node:1": { "version": "lts" },
    "ghcr.io/devcontainers/features/aws-cli:1": {},
    "ghcr.io/devcontainers/features/github-cli:1": {},
    "ghcr.io/devcontainers/features/terraform:1": {}
  },
  "customizations": {
    "vscode": {
      "extensions": [
        "Shopify.ruby-lsp",
        "bradlc.vscode-tailwindcss",
        "esbenp.prettier-vscode",
        "hashicorp.terraform"
      ]
    }
  },
  "postCreateCommand": "bin/setup",
  "remoteUser": "root"
}
```

- [ ] **Step 2: Write `.devcontainer/workspace.Dockerfile`**

Content:

```dockerfile
# Workspace image for FaleCom development.
#
# - Ruby 4.0.2 (matches .ruby-version)
# - Node LTS baked in so Vite works for CLI users too (VS Code devcontainer
#   features add another copy, which is harmless).
# - postgresql-client for psql against the postgres service.
# - bundler + standard pre-installed so first-time `bundle install` is fast.

FROM ruby:4.0.2-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    git \
    gnupg \
    libpq-dev \
    libyaml-dev \
    postgresql-client \
    pkg-config \
    tzdata \
  && rm -rf /var/lib/apt/lists/*

# Node LTS via NodeSource (needed for Vite in Phase 1B).
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
  && apt-get install -y --no-install-recommends nodejs \
  && rm -rf /var/lib/apt/lists/*

# Bundler + standardrb prebaked.
RUN gem install bundler:2.5.23 standard

WORKDIR /workspaces/falecom

# Keep the container alive; commands are run via `docker compose exec`.
CMD ["sleep", "infinity"]
```

---

## Task 6: Docker Compose files

**Files:**
- Create: `/Users/cooper/dev/falecom/infra/docker-compose.yml`
- Create: `/Users/cooper/dev/falecom/infra/docker-compose.prod.yml`

- [ ] **Step 1: Write `infra/docker-compose.yml`**

Content:

```yaml
# Development runtime for FaleCom.
#
# Services:
#   - workspace: dev container where all Ruby / Rails / test commands run.
#   - postgres:  shared Postgres 16 for the Rails app + Solid trio.
#
# Channel-related services (app, app-jobs, dev-webhook, whatsapp-cloud, zapi,
# ...) will be added by subsequent specs. Placeholders are intentionally left
# commented out so this file is not churned by unrelated work.

name: falecom

services:
  workspace:
    build:
      context: ../.devcontainer
      dockerfile: workspace.Dockerfile
    volumes:
      - ..:/workspaces/falecom:cached
      - workspace-bundle:/usr/local/bundle
    environment:
      DATABASE_URL: postgres://falecom:falecom@postgres:5432/falecom_development
      RAILS_ENV: development
    command: sleep infinity
    depends_on:
      postgres:
        condition: service_healthy

  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: falecom
      POSTGRES_PASSWORD: falecom
      POSTGRES_DB: falecom_development
    volumes:
      - postgres-data:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "falecom"]
      interval: 5s
      timeout: 5s
      retries: 10

  # Placeholders for future services. Uncomment when the owning spec lands.
  #
  # app:
  #   build: ../packages/app
  #   command: bin/rails server -b 0.0.0.0
  #   ports: ["3000:3000"]
  #   depends_on: [postgres]
  #
  # app-jobs:
  #   build: ../packages/app
  #   command: bin/jobs start
  #   depends_on: [postgres]
  #
  # dev-webhook:
  #   build: ../infra/dev-webhook
  #   ports: ["4000:4000"]

volumes:
  postgres-data:
  workspace-bundle:
```

- [ ] **Step 2: Write `infra/docker-compose.prod.yml`**

Content:

```yaml
# THIS FILE IS REFERENCE ONLY.
#
# FaleCom's production deploy runs on AWS (API Gateway + SQS + per-channel
# containers + the Rails app on managed compute). See infra/terraform/ for the
# real production manifest. This compose file exists so developers can skim a
# single file to understand the production topology — do NOT use it to deploy.

name: falecom-prod

services:
  # Intentionally empty until the production compose topology is specced.
  # This file is kept so `docker compose -f infra/docker-compose.prod.yml config`
  # parses cleanly and CI can at least lint the YAML shape.
  _placeholder:
    image: busybox:latest
    command: ["true"]
    profiles: ["disabled"]
```

- [ ] **Step 3: Verify compose parses**

Run (host): `docker compose -f /Users/cooper/dev/falecom/infra/docker-compose.yml config --services`

Expected (exactly two lines, order may vary):
```
postgres
workspace
```

Run (host): `docker compose -f /Users/cooper/dev/falecom/infra/docker-compose.prod.yml config --services`

Expected: one line — `_placeholder`.

---

## Task 7: Build the workspace image and start services

**Files:** none — runtime-only.

- [ ] **Step 1: Build the workspace image**

Run (host): `cd /Users/cooper/dev/falecom && docker compose -f infra/docker-compose.yml build workspace`

Expected: a successful build ending with `=> => naming to docker.io/library/falecom-workspace` (or similar) and no `ERROR` lines. First build may take 3–6 minutes (apt + Node + gems).

- [ ] **Step 2: Start postgres + workspace in detached mode**

Run (host): `cd /Users/cooper/dev/falecom && docker compose -f infra/docker-compose.yml up -d workspace postgres`

Expected: `Network falecom_default Created`, `Container falecom-postgres-1 Healthy`, `Container falecom-workspace-1 Started`.

- [ ] **Step 3: Smoke-test that the workspace can reach postgres**

Run (workspace):
```bash
docker compose -f /Users/cooper/dev/falecom/infra/docker-compose.yml exec workspace bash -lc 'ruby -v && psql "$DATABASE_URL" -c "select 1;"'
```

Expected:
```
ruby 4.0.2 ...
 ?column?
----------
        1
(1 row)
```

If either command fails, STOP and diagnose — every subsequent task depends on this.

---

## Task 8: Rails 8.1.3 scaffold

**Files:** a Rails tree is generated under `/Users/cooper/dev/falecom/packages/app/`. The only files this task hand-edits after the generator are listed in Task 9.

- [ ] **Step 1: Scaffold the app**

Run (workspace):
```bash
docker compose -f /Users/cooper/dev/falecom/infra/docker-compose.yml exec workspace bash -lc '
  cd /workspaces/falecom &&
  gem install rails -v 8.1.3 &&
  rails _8.1.3_ new packages/app \
    --database=postgresql \
    --devcontainer \
    --skip-asset-pipeline \
    --skip-javascript
'
```

Expected (last lines):
```
  create  packages/app/
  ...
    run  bundle install
  Bundle complete!
    run  bundle binstubs bundler
```

And no `ERROR` / `error` lines outside gem version warnings.

- [ ] **Step 2: Confirm the scaffold landed on the host**

Run (host):
```bash
ls /Users/cooper/dev/falecom/packages/app/bin/rails \
   /Users/cooper/dev/falecom/packages/app/config/application.rb \
   /Users/cooper/dev/falecom/packages/app/Gemfile
```

Expected: all three files exist. The volume mount is what makes this work — if they're not on the host, the mount is broken and the rest of the plan will fail.

- [ ] **Step 3: Remove the Rails-generated devcontainer**

Per spec §2: "Rails-generated devcontainer files at `packages/app/.devcontainer` are deleted after generation."

Run (host): `rm -rf /Users/cooper/dev/falecom/packages/app/.devcontainer`

Verify: `ls /Users/cooper/dev/falecom/packages/app/.devcontainer 2>&1 | head -1`

Expected: `ls: ... No such file or directory`.

---

## Task 9: Point Rails at the Docker postgres service

**Files:** Modify: `/Users/cooper/dev/falecom/packages/app/config/database.yml`

- [ ] **Step 1: Rewrite `database.yml`**

Overwrite `packages/app/config/database.yml` entirely with:

```yaml
default: &default
  adapter: postgresql
  encoding: unicode
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  host: <%= ENV.fetch("DATABASE_HOST") { "postgres" } %>
  username: <%= ENV.fetch("DATABASE_USER") { "falecom" } %>
  password: <%= ENV.fetch("DATABASE_PASSWORD") { "falecom" } %>
  port: 5432

development:
  <<: *default
  database: falecom_development

test:
  <<: *default
  database: falecom_test

production:
  primary:
    <<: *default
    database: falecom_production
    username: <%= ENV["FALECOM_DATABASE_USERNAME"] %>
    password: <%= ENV["FALECOM_DATABASE_PASSWORD"] %>
  cache:
    <<: *default
    database: falecom_production_cache
    migrations_paths: db/cache_migrate
  queue:
    <<: *default
    database: falecom_production_queue
    migrations_paths: db/queue_migrate
  cable:
    <<: *default
    database: falecom_production_cable
    migrations_paths: db/cable_migrate
```

Note: the development/test single-DB layout keeps the Solid trio colocated with application data, which satisfies "no external dependencies" (spec §4). Production still uses separate DBs per Rails 8.1's default.

- [ ] **Step 2: Create the test DB and confirm Rails boots**

Run (workspace):
```bash
docker compose -f /Users/cooper/dev/falecom/infra/docker-compose.yml exec workspace bash -lc '
  cd /workspaces/falecom/packages/app &&
  bin/rails db:prepare &&
  bin/rails runner "puts Rails.env; puts ActiveRecord::Base.connection.adapter_name"
'
```

Expected:
```
development
PostgreSQL
```

If the connection fails, STOP and diagnose the `database.yml` / compose env pair before moving on.

---

## Task 10: Install Solid Queue

**Files:** Auto-generated — `packages/app/config/queue.yml`, `packages/app/db/queue_schema.rb`, migrations under `db/migrate/`.

- [ ] **Step 1: Run the installer**

Run (workspace):
```bash
docker compose -f /Users/cooper/dev/falecom/infra/docker-compose.yml exec workspace bash -lc '
  cd /workspaces/falecom/packages/app &&
  bin/rails solid_queue:install
'
```

Expected: lines ending with `create  config/queue.yml` and `create  db/queue_schema.rb` (or migrations in `db/migrate/`). The installer also sets `config.active_job.queue_adapter = :solid_queue` in `config/environments/production.rb` and adds `config.solid_queue.connects_to = { database: { writing: :queue } }` where appropriate.

- [ ] **Step 2: Set Solid Queue as the Active Job adapter in development + test**

Modify `packages/app/config/application.rb` — inside `class Application < Rails::Application`, add:

```ruby
    config.active_job.queue_adapter = :solid_queue
```

(Rails 8.1 sets this in production automatically; we want it everywhere for parity with prod.)

- [ ] **Step 3: Verify**

Run (workspace):
```bash
docker compose -f /Users/cooper/dev/falecom/infra/docker-compose.yml exec workspace bash -lc '
  cd /workspaces/falecom/packages/app &&
  test -f config/queue.yml && echo "queue.yml present" &&
  bin/rails runner "puts Rails.application.config.active_job.queue_adapter"
'
```

Expected:
```
queue.yml present
solid_queue
```

---

## Task 11: Install Solid Cable

**Files:** Auto-generated — `packages/app/config/cable.yml` (overwritten), migrations.

- [ ] **Step 1: Run the installer**

Run (workspace):
```bash
docker compose -f /Users/cooper/dev/falecom/infra/docker-compose.yml exec workspace bash -lc '
  cd /workspaces/falecom/packages/app &&
  bin/rails solid_cable:install
'
```

Expected: `create  config/cable.yml` and migrations in `db/cable_migrate/` or `db/migrate/`.

- [ ] **Step 2: Confirm `config/cable.yml` uses solid_cable**

Run (workspace):
```bash
docker compose -f /Users/cooper/dev/falecom/infra/docker-compose.yml exec workspace bash -lc '
  cd /workspaces/falecom/packages/app &&
  grep -E "adapter:\s*solid_cable" config/cable.yml
'
```

Expected: a matching line in `development:` / `production:` / both.

If `cable.yml` still references `async` or `redis`, STOP — the installer did not run as expected.

---

## Task 12: Install Solid Cache

**Files:** Auto-generated — `packages/app/config/cache.yml`, migrations.

- [ ] **Step 1: Run the installer**

Run (workspace):
```bash
docker compose -f /Users/cooper/dev/falecom/infra/docker-compose.yml exec workspace bash -lc '
  cd /workspaces/falecom/packages/app &&
  bin/rails solid_cache:install
'
```

Expected: `create  config/cache.yml`, migrations generated. Installer also sets `config.cache_store = :solid_cache_store` in `config/environments/production.rb`.

- [ ] **Step 2: Set Solid Cache as the cache store in development + test**

Modify `packages/app/config/environments/development.rb`:
- Find the existing `config.cache_store = ...` line (if any) or the block that switches between `:memory_store` and `:null_store` based on `caching-dev.txt`.
- Replace the entire caching block with:

```ruby
  config.cache_store = :solid_cache_store
```

Modify `packages/app/config/environments/test.rb`:
- Replace the existing `config.cache_store = :null_store` (if present) with:

```ruby
  config.cache_store = :solid_cache_store
```

- [ ] **Step 3: Verify**

Run (workspace):
```bash
docker compose -f /Users/cooper/dev/falecom/infra/docker-compose.yml exec workspace bash -lc '
  cd /workspaces/falecom/packages/app &&
  test -f config/cache.yml && echo "cache.yml present" &&
  bin/rails runner "puts Rails.cache.class.name"
'
```

Expected:
```
cache.yml present
SolidCache::Store
```

---

## Task 13: Apply all migrations (Solid trio)

**Files:** `packages/app/db/schema.rb` (and any per-DB schema files) updated in place.

- [ ] **Step 1: Run migrations**

Run (workspace):
```bash
docker compose -f /Users/cooper/dev/falecom/infra/docker-compose.yml exec workspace bash -lc '
  cd /workspaces/falecom/packages/app &&
  bin/rails db:migrate &&
  bin/rails db:migrate:status | tail -20
'
```

Expected: every migration shows `up`. No `down` rows. The list includes entries whose names contain `solid_queue`, `solid_cable`, and `solid_cache` (names vary by Rails minor).

- [ ] **Step 2: Confirm the Solid trio tables exist**

Run (workspace):
```bash
docker compose -f /Users/cooper/dev/falecom/infra/docker-compose.yml exec workspace bash -lc '
  cd /workspaces/falecom/packages/app &&
  bin/rails runner "
    tables = ActiveRecord::Base.connection.tables
    %w[solid_queue_jobs solid_cable_messages solid_cache_entries].each do |t|
      raise %(missing table: #{t}) unless tables.include?(t)
      puts %(ok: #{t})
    end
  "
'
```

Expected:
```
ok: solid_queue_jobs
ok: solid_cable_messages
ok: solid_cache_entries
```

If any table is missing, STOP and report — one of the three installers didn't run cleanly.

---

## Task 14: Rails 8 authentication generator

**Files:** Auto-generated by the generator. Expected set (verify each in Step 2):
- `packages/app/app/models/user.rb`
- `packages/app/app/models/session.rb`
- `packages/app/app/models/current.rb`
- `packages/app/app/controllers/concerns/authentication.rb`
- `packages/app/app/controllers/sessions_controller.rb`
- `packages/app/app/controllers/passwords_controller.rb`
- `packages/app/app/views/sessions/new.html.erb`
- `packages/app/app/views/passwords/new.html.erb`
- `packages/app/app/views/passwords/edit.html.erb`
- `packages/app/app/mailers/passwords_mailer.rb`
- `packages/app/app/views/passwords_mailer/reset.{html,text}.erb`
- `packages/app/db/migrate/*_create_users.rb`
- `packages/app/db/migrate/*_create_sessions.rb`

- [ ] **Step 1: Run the generator**

Run (workspace):
```bash
docker compose -f /Users/cooper/dev/falecom/infra/docker-compose.yml exec workspace bash -lc '
  cd /workspaces/falecom/packages/app &&
  bin/rails generate authentication
'
```

Expected: `create` lines for each file above and (if not already) the bcrypt gem is added to `Gemfile` + `bundle install` runs.

- [ ] **Step 2: Verify every expected file landed**

Run (workspace):
```bash
docker compose -f /Users/cooper/dev/falecom/infra/docker-compose.yml exec workspace bash -lc '
  cd /workspaces/falecom/packages/app &&
  for f in \
    app/models/user.rb \
    app/models/session.rb \
    app/models/current.rb \
    app/controllers/concerns/authentication.rb \
    app/controllers/sessions_controller.rb \
    app/controllers/passwords_controller.rb \
    app/views/sessions/new.html.erb \
    app/mailers/passwords_mailer.rb \
  ; do
    test -f "$f" && echo "ok: $f" || { echo "missing: $f"; exit 1; }
  done &&
  ls db/migrate/*_create_users.rb db/migrate/*_create_sessions.rb
'
```

Expected: nine `ok: …` lines, then paths to the two migrations. If any `missing:` appears, STOP — the generator output differs from what Phase 1B depends on.

- [ ] **Step 3: Verify the User model's key contract**

Run (workspace):
```bash
docker compose -f /Users/cooper/dev/falecom/infra/docker-compose.yml exec workspace bash -lc '
  cd /workspaces/falecom/packages/app &&
  grep -q "has_secure_password" app/models/user.rb && echo "ok: has_secure_password" &&
  grep -q "has_many :sessions" app/models/user.rb && echo "ok: has_many :sessions" &&
  grep -q "belongs_to :user" app/models/session.rb && echo "ok: belongs_to :user"
'
```

Expected three `ok:` lines. If any fails, the generator produced unexpected output — STOP.

- [ ] **Step 4: Migrate users + sessions**

Run (workspace):
```bash
docker compose -f /Users/cooper/dev/falecom/infra/docker-compose.yml exec workspace bash -lc '
  cd /workspaces/falecom/packages/app &&
  bin/rails db:migrate &&
  bin/rails runner "
    User.new.tap do |u|
      raise %(User missing :email_address) unless u.respond_to?(:email_address)
      raise %(User missing :password_digest) unless u.respond_to?(:password_digest)
    end
    puts %(User schema ok)
    raise %(users table missing) unless ActiveRecord::Base.connection.tables.include?(%(users))
    raise %(sessions table missing) unless ActiveRecord::Base.connection.tables.include?(%(sessions))
    puts %(tables ok)
  "
'
```

Expected:
```
User schema ok
tables ok
```

---

## Task 15: Switch test framework to RSpec

**Files:**
- Modify: `packages/app/Gemfile` (add rspec-rails, remove `rubocop-rails-omakase`)
- Delete: `packages/app/test/` and `packages/app/.rubocop.yml`
- Create: `packages/app/spec/rails_helper.rb`, `packages/app/spec/spec_helper.rb` (via generator)

- [ ] **Step 1: Add `rspec-rails`, remove `rubocop-rails-omakase` from `packages/app/Gemfile`**

Open `packages/app/Gemfile`. Find the `group :development, :test do` block (it's the one that already has `debug` / `brakeman` / etc.). Inside it, add:

```ruby
  gem "rspec-rails", "~> 7.1"
```

Then find the `gem "rubocop-rails-omakase"` line (in the `group :development do` block) and **delete it** entirely.

- [ ] **Step 2: Install and generate RSpec scaffolding**

Run (workspace):
```bash
docker compose -f /Users/cooper/dev/falecom/infra/docker-compose.yml exec workspace bash -lc '
  cd /workspaces/falecom/packages/app &&
  bundle install &&
  bin/rails generate rspec:install
'
```

Expected: `create  .rspec`, `create  spec/spec_helper.rb`, `create  spec/rails_helper.rb`.

- [ ] **Step 3: Delete Rails' Minitest tree and rubocop config**

Run (host):
```bash
rm -rf /Users/cooper/dev/falecom/packages/app/test
rm -f /Users/cooper/dev/falecom/packages/app/.rubocop.yml
```

Verify: `ls /Users/cooper/dev/falecom/packages/app/test 2>&1 | head -1` → `ls: ... No such file or directory`.

- [ ] **Step 4: Write the boot smoke spec**

Write `/Users/cooper/dev/falecom/packages/app/spec/system_boot_spec.rb` with content:

```ruby
require "rails_helper"

RSpec.describe "Rails 8.1 application boot" do
  it "loads the test environment" do
    expect(Rails.env).to eq("test")
  end

  it "connects to Postgres" do
    expect(ActiveRecord::Base.connection.adapter_name).to eq("PostgreSQL")
    expect(ActiveRecord::Base.connection.execute("select 1 as n").first["n"]).to eq(1)
  end

  it "has the User model from the authentication generator" do
    expect(User.new).to be_a(ApplicationRecord)
    expect(User.new).to respond_to(:email_address)
    expect(User.new).to respond_to(:password_digest)
  end

  it "has the Session model from the authentication generator" do
    expect(Session.new).to be_a(ApplicationRecord)
    expect(Session.reflect_on_association(:user)).not_to be_nil
  end

  it "has the Solid trio tables" do
    tables = ActiveRecord::Base.connection.tables
    expect(tables).to include("solid_queue_jobs")
    expect(tables).to include("solid_cable_messages")
    expect(tables).to include("solid_cache_entries")
  end

  it "uses Solid Queue as the Active Job adapter" do
    expect(Rails.application.config.active_job.queue_adapter).to eq(:solid_queue)
  end

  it "uses Solid Cache as the cache store" do
    expect(Rails.cache.class.name).to include("SolidCache")
  end
end
```

- [ ] **Step 5: Run the spec**

Run (workspace):
```bash
docker compose -f /Users/cooper/dev/falecom/infra/docker-compose.yml exec workspace bash -lc '
  cd /workspaces/falecom/packages/app &&
  bin/rails db:prepare RAILS_ENV=test &&
  bundle exec rspec spec/system_boot_spec.rb --format documentation
'
```

Expected: `7 examples, 0 failures, 0 pending`.

If any example fails, STOP. Fix the cause (usually a config in `database.yml` or an environment file); do not mark examples pending.

---

## Task 16: Root `bundle install` + standardrb pass

**Files:** `/Users/cooper/dev/falecom/Gemfile.lock` (generated).

- [ ] **Step 1: Install the root Gemfile inside the workspace**

Run (workspace):
```bash
docker compose -f /Users/cooper/dev/falecom/infra/docker-compose.yml exec workspace bash -lc '
  cd /workspaces/falecom &&
  bundle install
'
```

Expected: `Bundle complete! 1 Gemfile dependency, N gems now installed.`

- [ ] **Step 2: Run standardrb with --fix once (to normalize Rails scaffold)**

Run (workspace):
```bash
docker compose -f /Users/cooper/dev/falecom/infra/docker-compose.yml exec workspace bash -lc '
  cd /workspaces/falecom &&
  bundle exec standardrb --fix || true
'
```

The `|| true` is intentional — we want the fixer to pass through, then the clean pass in Step 3 to enforce zero offenses.

- [ ] **Step 3: Run standardrb clean**

Run (workspace):
```bash
docker compose -f /Users/cooper/dev/falecom/infra/docker-compose.yml exec workspace bash -lc '
  cd /workspaces/falecom &&
  bundle exec standardrb
'
```

Expected: `no offenses detected` (wording may vary; what matters is exit code 0 and no files listed as problematic).

If offenses remain after `--fix`, examine each — they are almost always in Rails-generated files and either fall in a blind spot of `--fix` or are semantic issues. Fix them inline; do not add broad ignores.

---

## Task 17: `bin/setup` bootstrap script

**Files:** Create `/Users/cooper/dev/falecom/bin/setup`.

- [ ] **Step 1: Write `bin/setup`**

Content:

```bash
#!/usr/bin/env bash
# FaleCom repo bootstrap.
#
# Idempotent: safe to run repeatedly. Runs inside the workspace devcontainer
# (invoked by devcontainer.json's postCreateCommand). Also safe to run on a
# host that has Ruby 4.0.2 available via mise/asdf.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

echo "==> Installing root dev tooling (standardrb)"
bundle install

echo "==> Installing app gems"
(cd packages/app && bundle install)

echo "==> Preparing database (create if missing, migrate, seed)"
(cd packages/app && bin/rails db:prepare)

echo "==> Seeding dev user (idempotent)"
(cd packages/app && bin/rails runner '
  email = "dev@falecom.test"
  unless User.exists?(email_address: email)
    User.create!(
      email_address: email,
      password: "falecom-dev-password",
      password_confirmation: "falecom-dev-password"
    )
    puts "Seeded dev user #{email} (password: falecom-dev-password)"
  else
    puts "Dev user #{email} already present"
  end
')

echo "==> Done. Next: cd packages/app && bin/dev (available after Phase 1B)."
```

- [ ] **Step 2: Make it executable**

Run (host): `chmod +x /Users/cooper/dev/falecom/bin/setup`

- [ ] **Step 3: Verify idempotency**

Run (workspace):
```bash
docker compose -f /Users/cooper/dev/falecom/infra/docker-compose.yml exec workspace bash -lc '
  cd /workspaces/falecom &&
  bin/setup &&
  bin/setup
'
```

Expected: both runs finish with `Done.`. The second run prints `Dev user dev@falecom.test already present` (proving idempotency).

---

## Task 18: GitHub Actions CI

**Files:** Create `/Users/cooper/dev/falecom/.github/workflows/ci.yml`.

- [ ] **Step 1: Write `.github/workflows/ci.yml`**

Content:

```yaml
name: CI

on:
  pull_request:
  push:
    branches: [main]

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  lint:
    name: standardrb (root)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: 4.0.2
          bundler-cache: true
      - run: bundle exec standardrb

  app-tests:
    name: packages/app — rspec
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16-alpine
        env:
          POSTGRES_USER: falecom
          POSTGRES_PASSWORD: falecom
          POSTGRES_DB: falecom_test
        ports: ["5432:5432"]
        options: >-
          --health-cmd="pg_isready -U falecom"
          --health-interval=5s
          --health-timeout=5s
          --health-retries=10
    env:
      RAILS_ENV: test
      DATABASE_HOST: localhost
      DATABASE_USER: falecom
      DATABASE_PASSWORD: falecom
    defaults:
      run:
        working-directory: packages/app
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: 4.0.2
          bundler-cache: true
          working-directory: packages/app
      - run: bin/rails db:prepare
      - run: bundle exec rspec
```

- [ ] **Step 2: Verify YAML parses**

Run (host): `python3 -c 'import yaml; yaml.safe_load(open("/Users/cooper/dev/falecom/.github/workflows/ci.yml"))' && echo OK`

Expected: `OK`.

(CI actually running is verified at the end of the plan, when the PR is opened.)

---

## Task 19: Acceptance criteria walkthrough (spec §5, Phase 1A)

Execute each numbered criterion below in order. Each must pass before committing.

- [ ] **AC-1: Workspace starts**

Run (host):
```bash
cd /Users/cooper/dev/falecom &&
docker compose -f infra/docker-compose.yml ps --status running --services
```

Expected (both on separate lines, order may vary):
```
postgres
workspace
```

- [ ] **AC-2: `bin/setup` completes**

Run (workspace):
```bash
docker compose -f /Users/cooper/dev/falecom/infra/docker-compose.yml exec workspace bash -lc '
  cd /workspaces/falecom && bin/setup
'
```

Expected: ends with `Done.`, no non-zero exit.

- [ ] **AC-3: Migrations applied**

Run (workspace):
```bash
docker compose -f /Users/cooper/dev/falecom/infra/docker-compose.yml exec workspace bash -lc '
  cd /workspaces/falecom/packages/app &&
  bin/rails db:migrate:status | tail -20
'
```

Expected: every line starts with `up`. Names include Solid Queue + Solid Cable + Solid Cache + CreateUsers + CreateSessions.

- [ ] **AC-4: `bundle exec rspec` green**

Run (workspace):
```bash
docker compose -f /Users/cooper/dev/falecom/infra/docker-compose.yml exec workspace bash -lc '
  cd /workspaces/falecom/packages/app && bundle exec rspec
'
```

Expected: `7 examples, 0 failures`.

- [ ] **AC-5: `bundle exec standardrb` green at root**

Run (workspace):
```bash
docker compose -f /Users/cooper/dev/falecom/infra/docker-compose.yml exec workspace bash -lc '
  cd /workspaces/falecom && bundle exec standardrb
'
```

Expected: exit 0, no offenses.

- [ ] **AC-6: CI (verified after PR opens)**

See Task 20 — the PR exercise confirms AC-6.

---

## Task 20: Commit and push

Commit strategy: one PR, multiple logical commits. Each commit message follows Conventional Commits (per `CLAUDE.md`).

- [ ] **Commit 1: root config + devcontainer + compose**

Run (host):
```bash
cd /Users/cooper/dev/falecom &&
git add .ruby-version Gemfile Gemfile.lock .standard.yml .gitignore \
        .devcontainer/ infra/docker-compose.yml infra/docker-compose.prod.yml \
        infra/dev-webhook/.gitkeep infra/terraform/.gitkeep \
        packages/channels/.gitkeep packages/falecom_channel/.gitkeep &&
git commit -m "$(cat <<'EOF'
chore: add devcontainer, compose, and monorepo placeholders

Establishes the reproducible dev environment: workspace Dockerfile (Ruby
4.0.2 + Node LTS + postgresql-client), docker-compose.yml with workspace +
postgres:16-alpine, and placeholder directories for future packages and
infra. Root Gemfile pins standard 1.50 for the monorepo-wide lint.
EOF
)"
```

- [ ] **Commit 2: Rails 8.1.3 scaffold + database config**

Run (host):
```bash
cd /Users/cooper/dev/falecom &&
git add packages/app &&
git commit -m "$(cat <<'EOF'
feat: scaffold Rails 8.1.3 app with Postgres + Solid trio

Rails 8.1.3 in packages/app (--skip-asset-pipeline --skip-javascript so
Phase 1B can install Vite + Tailwind cleanly). database.yml points at the
compose postgres service in dev/test and uses separate DBs in prod for
Solid Cache/Queue/Cable. Solid Queue, Cable, and Cache installers run;
adapter + cache store set in development and test for prod parity.
EOF
)"
```

- [ ] **Commit 3: Rails 8 authentication generator**

Run (host):
```bash
cd /Users/cooper/dev/falecom &&
git add packages/app &&
git commit -m "$(cat <<'EOF'
feat: add Rails 8 authentication generator output

Users, Sessions, and Current models from `bin/rails generate
authentication`. Migrations create users (email_address, password_digest)
and sessions (user_id, token, ip_address, user_agent). bcrypt added to the
app Gemfile.
EOF
)"
```

- [ ] **Commit 4: RSpec + smoke spec**

Run (host):
```bash
cd /Users/cooper/dev/falecom &&
git add packages/app &&
git commit -m "$(cat <<'EOF'
chore: switch test framework to RSpec with a boot smoke spec

rspec-rails 7.1 replaces Minitest (test/ tree removed). One smoke spec
(spec/system_boot_spec.rb) covers: Rails boot, Postgres connection,
User/Session model presence, Solid trio tables, active job adapter, and
cache store. rubocop-rails-omakase removed from the app Gemfile in favor
of the repo-wide standardrb.
EOF
)"
```

- [ ] **Commit 5: bin/setup + CI**

Run (host):
```bash
cd /Users/cooper/dev/falecom &&
git add bin/setup .github/workflows/ci.yml &&
git commit -m "$(cat <<'EOF'
ci: add bin/setup bootstrap and GitHub Actions workflow

bin/setup is idempotent: installs root + app gems, runs db:prepare, and
seeds the dev user (dev@falecom.test). The workflow runs standardrb at
root and rspec in packages/app against a Postgres 16 service container
on every PR and push to main.
EOF
)"
```

- [ ] **Step 6: Push and open the PR**

Run (host):
```bash
cd /Users/cooper/dev/falecom &&
git push -u origin phase-1a-backend-scaffold
```

Then open a PR via `gh pr create` with:
- Title: `feat(phase-1a): monorepo foundation — backend scaffold`
- Body referencing `docs/specs/01-monorepo-foundation.md` (Phase 1A) and this plan; include the manual testing guide, risk assessment (blast radius: new branch only, no shared infra touched), and screenshots omitted (no UI yet).

- [ ] **Step 7: Confirm CI passes on the PR**

Run (host): `gh pr checks --watch`

Expected: both `lint` and `app-tests` jobs conclude with `pass`. This satisfies AC-6.

---

## Self-review notes

Spec coverage audit (spec §2, Phase 1A):
- Ruby version pin → Task 2
- Root Gemfile → Task 2
- `.devcontainer/devcontainer.json` → Task 5
- `.devcontainer/workspace.Dockerfile` → Task 5
- `infra/docker-compose.yml` → Task 6
- `infra/docker-compose.prod.yml` → Task 6
- Rails 8.1 scaffold → Task 8
- Deletion of Rails-generated devcontainer → Task 8
- `database.yml` configured → Task 9
- Solid Queue install → Task 10
- Solid Cable install → Task 11
- Solid Cache install → Task 12
- Rails 8 auth generator → Task 14
- RSpec installed, Minitest removed → Task 15
- `bin/setup` script → Task 17
- CI pipeline → Task 18
- Empty directory placeholders → Task 4 (plus `docs/plans/` already used by this file)

Acceptance criteria (spec §5, Phase 1A): AC-1..AC-6 all mapped to Task 19 + the PR check in Task 20.

Risks called out in spec §6:
- JR Components compatibility → not touched in 1A, lives in 1B plan.
- Rails 8.1 vs 8.0 → resolved: 8.1.3 is GA as of 2026-03-24.
- Devcontainer build time → Task 7 Step 1 warns "3–6 minutes."
