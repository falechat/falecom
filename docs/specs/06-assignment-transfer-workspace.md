# Spec: Assignment, Transfer & Workspace

> **Phase:** 5 (Assignment, Transfer, Teams)
> **Execution Order:** 6 of 7 — after Spec 5
> **Date:** 2026-04-17
> **Status:** Draft — awaiting approval
> **Depends on:**
> - [Spec 2: Core Domain Models](./02-core-domain-models.md) (all models exist)
> - [Spec 4: Ingestion Pipeline](./04-ingestion-pipeline.md) (conversations are being created)
> - [Spec 5: Outbound Dispatch](./05-outbound-dispatch.md) (agents can reply)

---

## 1. What problem are we solving?

Conversations arrive and agents can reply, but there is no system to route conversations to the right people. Specifically:

- New conversations sit in `queued` status with no mechanism to assign them to agents.
- Agents see every conversation regardless of team membership — there is no access scoping.
- There is no way to transfer a conversation from one agent or team to another.
- The dashboard has no workspace concept — no "Mine", "Unassigned", or "My team" views.
- The conversation detail view has no timeline showing system events alongside messages.
- There is no central place to manage Channels, Teams, and Users (Admin CRUDs).
- Contact details and history are not surfaced to the agent during a conversation.

This spec implements the full assignment, transfer, and workspace experience described in `ARCHITECTURE.md § Workspace`, `§ Conversation Transfer`, and `§ Build Order → Phase 5`.

---

## 2. What is in scope?

### 2.1 `ConversationPolicy` — Authorization

A Pundit-style policy object that answers all authorization questions for a conversation. Used by controllers, Solid Cable channels, and services.

```ruby
class ConversationPolicy
  attr_reader :user, :conversation

  def initialize(user, conversation)
    @user = user
    @conversation = conversation
  end

  def can_view?
    return true if user.admin?
    user_channel_ids.include?(conversation.channel_id)
  end

  def can_reply?
    can_view? && conversation.assignee_id == user.id
  end

  # Can the agent self-assign an unassigned conversation?
  def can_pickup?
    can_view? && conversation.assignee_id.nil? && conversation.status == "queued"
  end

  def can_transfer?
    return true if user.admin?
    return true if user.supervisor? && can_view?
    return true if can_pickup?  # agents can pick up unassigned conversations
    conversation.assignee_id == user.id
  end

  def can_resolve?
    can_reply? || user.admin? || (user.supervisor? && can_view?)
  end

  private

  def user_channel_ids
    @user_channel_ids ||= user.teams
      .joins(:channel_teams)
      .pluck("channel_teams.channel_id")
      .uniq
  end
end
```

**Authorization rules (from ARCHITECTURE.md):**

| Actor role | Can view | Can reply | Can pickup (self-assign) | Can transfer | Can resolve |
|---|---|---|---|---|---|
| Agent | Conversations on channels their teams attend | Only if assigned to them | Unassigned queued conversations on their channels | If assigned OR if picking up unassigned | Only if assigned to them |
| Supervisor | Conversations on channels any of their teams attend | Only if assigned to them | Same as agent | Any conversation they can view | Any conversation they can view |
| Admin | All conversations | Only if assigned to them | Same as agent | Anything | Anything |

### 2.2 `Assignments::AutoAssign` Service

Automatically assigns incoming conversations to available agents.

```ruby
class Assignments::AutoAssign
  def self.call(conversation)
    channel = conversation.channel
    return unless channel.auto_assign?

    config = channel.auto_assign_config
    strategy = config["strategy"] || "round_robin"
    team_id = config["team_id"]

    team = team_id ? Team.find(team_id) : channel.teams.order(:id).first
    return unless team

    agent = pick_agent(team, strategy, config)
    return unless agent

    conversation.update!(
      assignee: agent,
      team: team,
      status: "assigned"
    )

    Events::Emit.call(
      name: "conversations:assigned",
      subject: conversation,
      actor: :system,
      payload: { assignee_id: agent.id, team_id: team.id, strategy: strategy }
    )

    broadcast_assignment(conversation)
  end
end
```

**Strategies:**

| Strategy | Logic |
|---|---|
| `round_robin` | Pick the online agent in the team who was least recently assigned a conversation. Uses `FOR UPDATE` lock on the selected user row. |
| `capacity` | Each agent has a configurable max capacity (`auto_assign_config["capacity"]`, default 10). Pick the first online agent below capacity, round-robin among ties. Uses `FOR UPDATE` lock. |

**Eligibility filter:**
- Only agents with `availability: "online"` are eligible.
- If no agent is online, the conversation stays `queued` — it will be assigned when an agent comes online (triggered by availability change).

### 2.3 Agent Availability

- [ ] **Availability toggle** in the dashboard navbar — dropdown with "Online", "Busy", "Offline".
- [ ] `PATCH /dashboard/users/availability` → updates `current_user.availability`.
- [ ] Emits `users:availability_changed` event.
- [ ] When an agent goes `online`, trigger `Assignments::AutoAssign` for all `queued` conversations on channels their teams attend (enqueued as a job to avoid blocking the request).
- [ ] When an agent goes `offline`, their queued conversations are NOT automatically unassigned — the agent keeps their assigned conversations. Only explicit unassign/transfer moves them.

### 2.4 Auto-Assign Trigger Points

Auto-assign runs at these moments:
1. **New conversation created** with `status: queued` (from `Ingestion::ProcessMessage` or after `Flows::Handoff`).
2. **Agent goes online** — check for unassigned conversations on their channels.

In all cases, auto-assign is enqueued as `AutoAssignJob.perform_later(conversation_id)` to keep the calling path fast.

### 2.5 `Assignments::Transfer` Service

Handles all three transfer types with a single service.

```ruby
class Assignments::Transfer
  def self.call(conversation:, to_team: nil, to_user: nil, note: nil, actor:)
    policy = ConversationPolicy.new(actor, conversation)
    raise FaleCom::AuthorizationError unless policy.can_transfer?

    # Validate target
    if to_team
      unless conversation.channel.teams.include?(to_team)
        raise FaleCom::ValidationError, "Team does not attend this channel"
      end
    end

    if to_user && to_team
      unless to_team.users.include?(to_user)
        raise FaleCom::ValidationError, "User is not a member of the target team"
      end
    end

    # Capture previous state
    from_team_id = conversation.team_id
    from_user_id = conversation.assignee_id

    # Apply transfer
    conversation.update!(
      team: to_team,
      assignee: to_user,
      status: to_user ? "assigned" : "queued"
    )

    # Optional note → system message
    if note.present?
      Messages::Create.call(
        conversation: conversation,
        direction: "outbound",
        content: note,
        content_type: "text",
        sender_type: "System",
        status: "received" # system messages are not sent to the provider
      )
    end

    # Emit event
    Events::Emit.call(
      name: "conversations:transferred",
      subject: conversation,
      actor: actor,
      payload: {
        from_team_id: from_team_id,
        to_team_id: to_team&.id,
        from_user_id: from_user_id,
        to_user_id: to_user&.id,
        note: note
      }
    )

    # Broadcast workspace updates
    broadcast_transfer(conversation, from_user_id, from_team_id)
  end
end
```

**Transfer types (determined by arguments):**

| Type | Arguments | Result |
|---|---|---|
| Reassign | `to_user: pedro` | Conversation moves to Pedro, same team |
| Team transfer | `to_team: finance` | Conversation moves to Finance team, unassigned (and triggers auto-assign for that team) |
| Team transfer + assign | `to_team: finance, to_user: maria` | Conversation moves to Finance, assigned to Maria |
| Unassign | `to_team: nil, to_user: nil` | Conversation goes to `queued` but remains in the current team. It is NOT immediately auto-assigned again. |

### 2.6 Transfer UI

- [ ] **Transfer button** on conversation detail view (visible only if `ConversationPolicy#can_transfer?`).
- [ ] **Transfer modal** (JR Components modal):
  - Team dropdown — filtered to teams that attend the conversation's channel (`channel.teams`).
  - User dropdown — filtered to members of the selected team. Optional (can transfer to team without picking a user).
  - Note textarea — optional free-text context for the receiving agent.
  - Submit button.
- [ ] `POST /dashboard/conversations/:id/transfer` → `Assignments::Transfer.call`.
- [ ] On success: modal closes, conversation updates in-place (or disappears from "Mine" if the agent transferred away).

### 2.7 Resolve / Reopen

- [ ] **Resolve button** — visible if `ConversationPolicy#can_resolve?`. Sets `status: resolved`.
- [ ] **Reopen** — when a contact sends a new message to a resolved conversation's contact_channel, `Conversations::ResolveOrCreate` creates a new conversation (already implemented in Spec 4). A future enhancement may allow explicit reopen.
- [ ] `POST /dashboard/conversations/:id/resolve` → service sets status, emits `conversations:resolved`, broadcasts.

### 2.8 Workspace Views

The dashboard conversation list implements filtered views. These are URL query parameters on the same route, not separate controllers.

**Route:** `GET /dashboard/conversations?view=mine&channel_id=X`

| View | Query | Description |
|---|---|---|
| `mine` (default) | `assignee_id = current_user.id` | Conversations assigned to me |
| `unassigned` | `assignee_id IS NULL AND status = 'queued'` | Conversations waiting for pickup |
| `team` | `team_id IN (my_team_ids)` | All conversations in my teams |
| `channel` | `channel_id = ?` | All conversations on a specific channel |
| `all` (admin only) | `1=1` | Everything |

**Shared behavior:**
- All views are scoped by `ConversationPolicy#can_view?` — an agent never sees conversations on channels their teams don't attend.
- Conversations sorted by `last_activity_at DESC` (most recent first).
- Turbo Frame navigation — switching views replaces the list without a full page reload.
- Pagination via Turbo Frame lazy loading or Pagy.

### 2.9 Conversation List Component

A ViewComponent rendering a single conversation row:

```
[Channel icon] [Contact name]         [Last message preview]  [Time]
               [Status badge] [Team]  [Assignee avatar]
```

- Channel icon varies by `channel_type`.
- Status badge: colored dot (blue=bot, yellow=queued, green=assigned, gray=resolved).
- Unread indicator: bold text if messages arrived since last agent view.
- Clicking a row navigates to the conversation detail (Turbo Frame target).

### 2.10 Conversation Timeline Component

The conversation detail view shows messages interleaved with system events.

```ruby
class ConversationTimeline::Component < ViewComponent::Base
  def initialize(conversation:)
    @items = build_timeline(conversation)
  end

  def build_timeline(conversation)
    messages = conversation.messages.order(:created_at)
    events = Event.where(subject: conversation).order(:created_at)

    (messages + events).sort_by(&:created_at)
  end
end
```

**Rendered items:**

| Item type | Visual |
|---|---|
| Inbound message | Left-aligned bubble, contact avatar |
| Outbound message (agent) | Right-aligned bubble, agent avatar, status checkmarks |
| Outbound message (bot) | Right-aligned bubble, bot icon |
| System message (transfer note) | Centered, muted text, no bubble |
| Event: `conversations:created` | Centered pill: "Conversation started" |
| Event: `conversations:assigned` | Centered pill: "Assigned to {agent}" |
| Event: `conversations:transferred` | Centered pill: "Transferred from {from} to {to}" |
| Event: `conversations:resolved` | Centered pill: "Resolved by {agent}" |
| Event: `flows:handoff` | Centered pill: "Bot handed off to {team}" |

| Event: `flows:handoff` | Centered pill: "Bot handed off to {team}" |

| Event: `flows:handoff` | Centered pill: "Bot handed off to {team}" |

### 2.11 The Three-Pane Layout (Workspace)

The main dashboard (`/dashboard`) uses a fixed-height, full-screen three-pane layout to minimize scrolling and keep context visible.

1.  **Left Pane (25% - Conversation List)**:
    - **Header**: Search bar + View Selector (Mine, Unassigned, All).
    - **List**: High-density cards. Unread messages show a blue dot. Active conversation is highlighted.
2.  **Center Pane (50% - Active Conversation)**:
    - **Header**: Contact Name, Channel icon, and Action Bar (Resolve, Transfer).
    - **Timeline**: Scrollable area with messages and system events. Newest at the bottom.
    - **Footer**: Reply area with auto-expanding textarea and "Send" button.
3.  **Right Pane (25% - Contact Context)**:
    - **Contact Profile**: Avatar, Name, and core fields (Phone, Email).
    - **Custom Attributes**: A list of key-value pairs (e.g., "Plan: Enterprise").
    - **Conversation History**: Chronological list of past `#display_id` for this contact.

### 2.12 Admin UI: Channels, Teams & Users

Admin screens (`/admin/*`) use standard data tables with search, sort, and pagination.

**Channels Table:**
| Field | Type | Description |
|---|---|---|
| Name | String | Friendly name (e.g., "WhatsApp Support") |
| Type | Badge | Icon + Provider (e.g., "WhatsApp Cloud") |
| Identifier | Code | The provider ID (Phone number or ID) |
| Active | Toggle | Quick enable/disable |
| Auto-Assign | Badge | Shows strategy (e.g., "Round Robin") |

**Teams Table:**
| Field | Type | Description |
|---|---|---|
| Name | String | Team name (e.g., "Sales") |
| Members | Avatar Stack | List of users in the team |
| Channels | Badge List | Channels attended by this team |

**Users Table:**
| Field | Type | Description |
|---|---|---|
| Name | String | Full name |
| Email | String | Login email |
| Role | Badge | Admin, Supervisor, or Agent |
| Teams | Badge List | Teams the user belongs to |
| Availability | Status Indicator | Online (Green), Busy (Yellow), Offline (Gray) |

### 2.13 Contact Management & Manual Creation

Agents and Admins can manage contacts independently of active conversations.

- **Manual Creation**: `POST /dashboard/contacts` creates a `Contact` and an optional `ContactChannel`. This allows agents to start conversations with people who haven't messaged the system yet.
- **Attributes**: Users can add ad-hoc attributes to contacts. These are stored in `additional_attributes` jsonb.
- **Notes**: Internal-only messages added to a conversation that don't go to the customer (sender: "System").
- **Integration Links**: If an attribute contains a URL (e.g., "CRM Link"), it renders as a clickable external link in the sidebar.

### 2.14 Real-Time Scoping (Solid Cable)

Turbo Streams broadcast conversation events per Channel. The agent's browser subscribes to the Channels their teams attend.

```ruby
class ConversationChannel < Turbo::StreamsChannel
  def subscribed
    channels = current_user.teams
      .joins(:channel_teams)
      .pluck("channel_teams.channel_id")
      .uniq

    channels.each do |channel_id|
      stream_from "conversations:channel:#{channel_id}"
    end

    # Also subscribe to personal stream
    stream_from "conversations:user:#{current_user.id}"
  end
end
```

**Broadcasts:**
- When a message is created → broadcast to `conversations:channel:#{channel_id}` (updates conversation list row) and to `conversation:#{conversation.id}` (appends message to timeline).
- When a conversation is assigned → broadcast to `conversations:user:#{assignee_id}` (appears in "Mine").
- When a conversation is transferred → broadcast remove to old assignee stream, broadcast append to new assignee stream.

### 2.12 Tests

- [ ] **`ConversationPolicy` specs:**
  - Agent can view conversation on their channel, cannot view others.
  - Agent can reply only if assigned.
  - Supervisor can transfer any conversation they can view.
  - Admin can do everything.

- [ ] **`Assignments::AutoAssign` specs:**
  - Round-robin picks the agent with fewest active assignments.
  - Capacity strategy respects max capacity.
  - Only online agents are eligible.
  - No eligible agents → conversation stays queued.

- [ ] **`Assignments::Transfer` specs:**
  - Reassign (User → User) — updates assignee, emits event.
  - Team transfer — updates team, status goes to queued.
  - Unassign — clears assignee, status goes to queued.
  - Note creates system message in thread.
  - Unauthorized transfer raises AuthorizationError.
  - Transfer to team that doesn't attend the channel raises ValidationError.

- [ ] **Workspace view request specs:**
  - `?view=mine` returns only conversations assigned to current user.
  - `?view=unassigned` returns only queued conversations on accessible channels.
  - Agent cannot see conversations on channels their teams don't attend.
  - Admin sees all conversations.

- [ ] **Conversation timeline component specs:**
  - Messages and events render in chronological order.
  - Transfer events show from/to information.
  - System messages render differently from user messages.

- [ ] **Solid Cable authorization spec:**
  - Agent subscribes only to their teams' channels.
  - Broadcasts reach the correct subscribers.

---

## 3. What is out of scope?

- **Approval workflow for transfers** — v1 is "if you have permission, it's done."
- **SLA tracking / response time metrics** — roadmap item.
- **Canned responses / knowledge base** — roadmap item.
- **Conversation search / filtering beyond workspace views** — follow-up.
- **Notifications (push, email, sound)** — follow-up spec.

---

## 4. What changes about the system?

After this spec:

- Conversations are automatically assigned to available agents based on configurable rules.
- Agents see only the conversations they should see, scoped by team → channel membership.
- Transfer between agents and teams is a first-class, audited operation.
- The dashboard has a full workspace experience with filtered views.
- The conversation detail view shows a rich timeline of messages and system events.
- Real-time updates are scoped — agents receive broadcasts only for their channels.

This implements `ARCHITECTURE.md § Workspace`, `§ Conversation Transfer`, `§ Build Order → Phase 5`.

---

## 5. Acceptance criteria

1. New `queued` conversation on a channel with `auto_assign: true` → automatically assigned to an online agent.
2. Agent toggles availability to "Online" → previously queued conversations on their channels are assigned.
3. Agent clicks "Transfer" → modal shows teams attending the channel → selecting team and user transfers the conversation → event appears in timeline.
4. Transfer with note → system message appears in conversation thread.
5. Agent in "Mine" view only sees their assigned conversations.
6. Agent in "Unassigned" view sees only queued conversations on their accessible channels.
7. Admin sees all conversations regardless of team membership.
8. Real-time: new message on a channel → conversation row updates for agents whose teams attend that channel, not for others.
9. Transfer: conversation disappears from sender's "Mine" view and appears in receiver's "Mine" view in real-time.
10. `bundle exec rspec` passes. `bundle exec standardrb` passes.

---

## 6. Risks

- **N+1 queries** — workspace views join across users → teams → channel_teams → channels → conversations. Mitigation: use `includes` / `joins` deliberately, test with `bullet` gem or query count assertions.
- **Auto-assign race conditions** — two conversations arriving simultaneously could both be assigned to the same agent, exceeding capacity. Mitigation: use database advisory locks or `WITH LOCK` in the auto-assign query.
- **Solid Cable subscription count** — if an agent is on many teams with many channels, they subscribe to many streams. Mitigation: Solid Cable handles this fine for dozens of streams; revisit if agents have hundreds of channels.

---

## 7. Decided Architecture (Previously Open Questions)

1. **Unread count** — Decided: **No unread count for v1**. Conversations with activity since the agent's last visit will be shown in **bold text**. Full unread counts will be implemented in a future phase with a dedicated tracking table.
2. **Conversation pickup** — Decided: **Yes**. Agents can explicitly "pick up" an unassigned conversation via a button that assigns it to them.
3. **Team-only transfer** — Decided: **Yes**. Transferring to a team immediately triggers the `AutoAssignJob` for that team if enabled.
