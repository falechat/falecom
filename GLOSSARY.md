# Glossary

Single source of truth for terminology used across the FaleCom codebase. When you introduce a new concept in code, add it here. When you find a term in code that isn't here, either add it or rename the code to use a term that is.

For architectural context behind these terms, see [`ARCHITECTURE.md`](./ARCHITECTURE.md).

---

## Domain

| Term | Definition |
|---|---|
| **Account** | Tenant boundary. Everything in the system belongs to an account |
| **User** | Internal person using the platform — agent, admin, supervisor. Authenticates into the dashboard |
| **Role** | Permission set assigned to a user: `admin`, `supervisor`, `agent` |
| **Team** | A group of users. Conversations can be routed to teams |
| **Contact** | The person interacting with the business through a channel. Not a user |
| **Channel** | A registered provider instance. Examples: "WhatsApp Vendas 5511999", "Instagram @loja_promo". Identified by `channel_type` + `identifier`. Holds credentials, auto-assign policy, active flow, and is where messages arrive |
| **ContactChannel** | Join between a Contact and a Channel, holding the `source_id` (WhatsApp number, Instagram PSID, etc.) that routes messages to the correct conversation |
| **Conversation** | A thread of messages between a contact and the team on one channel. Has a status and an assignee |
| **Message** | A single message in a conversation. Has direction (`inbound`/`outbound`), `content_type`, and `status` |
| **Workspace** | UI term. The filtered view of conversations a logged-in user has access to — composed of the channels their teams attend. Not a database entity. Users may see sub-views within: "Mine", "Unassigned", "My team", "By channel" |

## Conversation lifecycle

| Status | Meaning |
|---|---|
| `bot` | Flow is active, no human needed |
| `queued` | Waiting for an agent to pick up |
| `assigned` | Agent or team has it |
| `resolved` | Done |

| Term | Definition |
|---|---|
| **Transfer** | Moving a conversation from one assignee or team to another. Covers three cases: reassign (User → User same team), team transfer (Team A → Team B), and unassign (back to channel queue). All three emit `conversations:transferred` and optionally create a system message with a note |
| **Handoff** | Specifically the moment a flow transfers a conversation to a human (bot → queued). Distinct from human-to-human Transfer |

## Messaging pipeline

| Term | Definition |
|---|---|
| **Gateway** | AWS API Gateway (managed service). Receives provider webhooks and pushes raw bodies directly to the correct SQS queue. No code we maintain |
| **Channel Container** | A tiny Roda app — one per channel type — that pulls from its SQS queue, validates the provider signature, parses the provider payload, normalizes to the Common Ingestion Payload, and POSTs to the Rails API. Also exposes a `/send` endpoint for outbound |
| **Channel Registration** | A row in the `channels` table. The API refuses to ingest messages for channels that aren't registered and active |
| **Common Ingestion Payload** | The single normalized format the API accepts at `/internal/ingest`. Required common fields (`channel`, `contact`, `message`) + flexible `metadata` for provider-specific extras + `raw` for audit |
| **`falecom_channel`** | Internal gem shared by every channel container. Provides the SQS consumer loop, Payload schema, HMAC ingest client, and Roda base server for `/send` |

## Flow Engine

| Term | Definition |
|---|---|
| **Flow** | A stateful conversational script run by the bot before handing off to a human. Composed of nodes. Associated with one Channel |
| **Node** | A step in a flow. Types: `message`, `menu`, `collect`, `handoff`, `branch` |
| **Handoff** | The moment a flow transfers a conversation to a human team or agent. Sets `conversation.status` to `queued` |
| **ConversationFlow** | Per-conversation runtime state of a flow execution: current node, accumulated state, status |
| **Inactivity Threshold** | Per-flow setting (`inactivity_threshold_hours`) that decides whether a new message starts the flow from the root (full menu) or from a "how can I help?" prompt |

## Infrastructure

| Term | Definition |
|---|---|
| **Solid Queue** | Rails 8 Postgres-backed background job system. Used for all outbound dispatch, attachment downloads, automation rules, auto-resolve |
| **Solid Cable** | Rails 8 Postgres-backed WebSocket pub/sub. Used for real-time dashboard updates via Turbo Streams |
| **Solid Cache** | Rails 8 Postgres-backed cache store |
| **ViewComponent** | GitHub's component framework for Rails. Components are Ruby classes + ERB templates, testable in isolation |
| **JR Components** | Jetrockets' open-source Rails UI library. ViewComponent + TailwindCSS 4 + Stimulus. Copy/paste into the repo — no gem dependency |
| **dev-webhook** | Dev-only Roda app that mimics AWS API Gateway locally, so the ingestion pipeline can be exercised end-to-end without AWS |

## Dev environment

| Term | Definition |
|---|---|
| **Devcontainer** | The workspace definition at `.devcontainer/devcontainer.json`. Opened by VS Code / Cursor with the Dev Containers extension to attach into a pre-configured Ruby + tooling environment. Uses `infra/docker-compose.yml` as its service stack |
| **`bin/setup`** | Idempotent setup script at repo root. Runs `bundle install`, Vite asset install, `rails db:prepare`, and seeds dev accounts/channels. Called by `postCreateCommand` in the devcontainer; also the entry point for contributors not using the devcontainer |
| **Workspace service** | The `workspace` service in `docker-compose.yml`. Holds all developer tooling (Ruby, standardrb, node, aws-cli, terraform). The devcontainer attaches here. Does not exist in production. Unrelated to the UI-level "Workspace" in the Domain section above |

## Events

Events are module-prefixed, past-tense, written in snake_case. Every state-changing action in the system emits at least one event. See `ARCHITECTURE.md → Audit` for the principle behind this.

Full catalogue:

- **accounts:** `created`, `updated`
- **users:** `created`, `invited`, `activated`, `deactivated`, `signed_in`, `signed_out`, `role_changed`, `availability_changed`
- **teams:** `created`, `updated`, `deleted`
- **team_members:** `added`, `removed`
- **channels:** `registered`, `updated`, `activated`, `deactivated`, `deleted`
- **channel_teams:** `added`, `removed`
- **contacts:** `created`, `updated`, `merged`, `deleted`
- **contact_channels:** `created`, `deleted`
- **conversations:** `created`, `status_changed`, `assigned`, `unassigned`, `transferred`, `resolved`, `reopened`
- **messages:** `inbound`, `outbound`, `delivered`, `read`, `failed`
- **flows:** `created`, `updated`, `activated`, `deactivated`, `deleted`, `started`, `advanced`, `handoff`, `completed`, `abandoned`
- **automation_rules:** `created`, `updated`, `deleted`, `applied`

Adding a new capability means adding its event name here before writing the service.
