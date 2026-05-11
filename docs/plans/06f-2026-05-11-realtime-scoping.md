# Plan 06f: Real-Time Scoping (Solid Cable)

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans`.
> **Spec:** [06 — Assignment, Transfer & Workspace](../specs/06-assignment-transfer-workspace.md)
> **Date:** 2026-05-11
> **Status:** Draft — awaiting approval
> **Branch:** `plan-06f-realtime-scoping`
> **Depends on:** Plans 06a–06e (ConversationPolicy, AutoAssign, Transfer, workspace, timeline). This plan replaces the placeholder broadcast no-ops left in 06a + 06b with real Turbo Stream broadcasts and per-user subscription gating.

**Goal:** Wire scoped real-time updates: each agent subscribes only to streams for channels their teams attend plus a personal stream; every state change (`messages:inbound`, `messages:sent`/`delivered`, `conversations:assigned`, `conversations:transferred`, `conversations:resolved`) broadcasts to exactly the right streams. After this plan, the workspace updates live without F5: rows reorder on activity, mine fills up on assignment, transfers move conversations between users' "Mine" views, and message status checkmarks animate as the gem reports them.

**Architecture:** A custom `ConversationStreamsChannel < Turbo::StreamsChannel` overrides `subscribed` to compute the allowed stream names from `current_user`'s teams → channel_teams. The dashboard layout calls `turbo_stream_from "conversations:user:#{Current.user.id}"` for the personal stream and one `turbo_stream_from "conversations:channel:#{c.id}"` per accessible channel. Broadcasts move from the no-op placeholders into a single `Conversations::Broadcasts` module that knows the four targets: append/replace the row in `conversations:channel:#{cid}`, append message to `conversation:#{conv.id}`, remove/append for assignment changes on `conversations:user:#{uid}`. Spec 05 already broadcasts message rows for inbound + status changes; this plan harmonizes those calls under the new module so there's one place to read.

**Tech Stack:** Ruby 4.0.2, Rails 8.1.3, Turbo Rails 2.x (Solid Cable as backend, per Spec 01), RSpec 7.1. No new gems.

---

## Files to touch

### Create

- `packages/app/app/channels/conversation_streams_channel.rb`
- `packages/app/app/services/conversations/broadcasts.rb`

### Create — specs

- `packages/app/spec/channels/conversation_streams_channel_spec.rb`
- `packages/app/spec/services/conversations/broadcasts_spec.rb`
- `packages/app/spec/system/realtime_workspace_spec.rb` (Playwright system spec — exercises end-to-end via two browser sessions, but if the harness isn't Playwright, write it as a request-level integration spec that asserts on broadcast calls)

### Modify

- `packages/app/app/services/assignments/auto_assign.rb` — replace `broadcast_assignment` no-op with `Conversations::Broadcasts.assigned(conversation)`.
- `packages/app/app/services/assignments/transfer.rb` — call `Conversations::Broadcasts.transferred(conversation, from_user_id:, from_team_id:)`.
- `packages/app/app/services/conversations/resolve.rb` — call `Conversations::Broadcasts.resolved(conversation)`.
- `packages/app/app/services/ingestion/process_message.rb` — replace any inline broadcast with `Conversations::Broadcasts.message_appended(message)`.
- `packages/app/app/services/ingestion/process_status_update.rb` — call `Conversations::Broadcasts.message_status_changed(message)`.
- `packages/app/app/jobs/send_message_job.rb` — replace the `broadcast_status` placeholder from Plan 05a with `Conversations::Broadcasts.message_status_changed(message)`.
- `packages/app/app/views/layouts/application.html.erb` (or the dashboard layout) — subscribe via `turbo_stream_from`.

---

## Order of operations

1. **`Conversations::Broadcasts`** — the single source of truth for all four broadcast targets. Test with `ActionCable::TestHelper`.
2. **`ConversationStreamsChannel`** — subscription gating. Test allowed/forbidden cases with `ActionCable::Channel::TestCase`.
3. **Replace placeholders** in AutoAssign/Transfer/Resolve/ProcessMessage/ProcessStatusUpdate/SendMessageJob to call the module. One commit per service.
4. **Layout subscriptions.**
5. **System / integration spec** — two-session simulation (or its request-spec equivalent).
6. **Regression + PROGRESS.**

---

## What could go wrong

**Most likely:** an agent on many channels (10+) creates a fat layout with one `turbo_stream_from` per channel. Turbo handles dozens of streams fine, but verify the rendered HTML stays under a few KB. Mitigation: pluck the channel IDs once in the controller, render them in a tight loop, and avoid re-rendering on every Turbo Frame navigation by placing the subscriptions at the `application` layout level outside any frame.

**Least likely:** Solid Cable lags under load. Production tuning is out of scope; for v1 we accept Solid Cable's default polling and add a TODO in `docs/specs/06-*.md` to revisit if latency exceeds 1s.

---

## Task 1: `Conversations::Broadcasts`

**Files:**
- Create: `packages/app/app/services/conversations/broadcasts.rb`
- Test: `packages/app/spec/services/conversations/broadcasts_spec.rb`

- [ ] **Step 1: Failing spec**

```ruby
require "rails_helper"
RSpec.describe Conversations::Broadcasts do
  let(:channel) { create(:channel) }
  let(:user)    { create(:user) }
  let(:conv)    { create(:conversation, channel: channel, assignee: user) }

  it "message_appended broadcasts append to conversation:<id>" do
    msg = create(:message, conversation: conv, direction: "inbound", content: "yo")
    expect { described_class.message_appended(msg) }
      .to have_broadcasted_to("conversation:#{conv.id}").from_channel(Turbo::StreamsChannel)
  end

  it "message_appended also updates the conversation row in conversations:channel:<id>" do
    msg = create(:message, conversation: conv, direction: "inbound", content: "yo")
    expect { described_class.message_appended(msg) }
      .to have_broadcasted_to("conversations:channel:#{channel.id}").from_channel(Turbo::StreamsChannel)
  end

  it "assigned broadcasts to assignee's personal stream and the channel stream" do
    expect { described_class.assigned(conv) }
      .to have_broadcasted_to("conversations:user:#{user.id}")
      .and have_broadcasted_to("conversations:channel:#{channel.id}")
  end

  it "transferred sends remove to old user, append to new user" do
    old_user = create(:user)
    new_user = create(:user)
    conv.update!(assignee: new_user)
    expect { described_class.transferred(conv, from_user_id: old_user.id, from_team_id: nil) }
      .to have_broadcasted_to("conversations:user:#{old_user.id}")
      .and have_broadcasted_to("conversations:user:#{new_user.id}")
  end

  it "resolved broadcasts to the channel stream and the assignee" do
    expect { described_class.resolved(conv) }
      .to have_broadcasted_to("conversations:channel:#{channel.id}")
      .and have_broadcasted_to("conversations:user:#{user.id}")
  end

  it "message_status_changed targets the timeline + the row" do
    msg = create(:message, conversation: conv, direction: "outbound", status: "delivered")
    expect { described_class.message_status_changed(msg) }
      .to have_broadcasted_to("conversation:#{conv.id}")
      .and have_broadcasted_to("conversations:channel:#{channel.id}")
  end
end
```

- [ ] **Step 2: Implement**

```ruby
module Conversations
  module Broadcasts
    module_function

    def message_appended(message)
      conv = message.conversation
      Turbo::StreamsChannel.broadcast_append_to(
        "conversation:#{conv.id}", target: "messages", partial: "dashboard/conversations/timeline_message",
        locals: {message: message}
      )
      broadcast_row(conv)
    end

    def message_status_changed(message)
      conv = message.conversation
      Turbo::StreamsChannel.broadcast_replace_to(
        "conversation:#{conv.id}", target: ActionView::RecordIdentifier.dom_id(message),
        partial: "dashboard/conversations/timeline_message", locals: {message: message}
      )
      broadcast_row(conv)
    end

    def assigned(conversation)
      broadcast_row(conversation)
      if conversation.assignee_id
        Turbo::StreamsChannel.broadcast_prepend_to(
          "conversations:user:#{conversation.assignee_id}", target: "mine-list",
          partial: "dashboard/conversations/list_row", locals: {conversation: conversation}
        )
      end
    end

    def transferred(conversation, from_user_id:, from_team_id:)
      if from_user_id
        Turbo::StreamsChannel.broadcast_remove_to(
          "conversations:user:#{from_user_id}",
          target: ActionView::RecordIdentifier.dom_id(conversation)
        )
      end
      assigned(conversation)
      broadcast_row(conversation)
    end

    def resolved(conversation)
      broadcast_row(conversation)
      if conversation.assignee_id
        Turbo::StreamsChannel.broadcast_remove_to(
          "conversations:user:#{conversation.assignee_id}",
          target: ActionView::RecordIdentifier.dom_id(conversation)
        )
      end
    end

    def broadcast_row(conversation)
      Turbo::StreamsChannel.broadcast_replace_to(
        "conversations:channel:#{conversation.channel_id}",
        target: ActionView::RecordIdentifier.dom_id(conversation),
        partial: "dashboard/conversations/list_row", locals: {conversation: conversation}
      )
    end
  end
end
```

Add the partial `app/views/dashboard/conversations/_list_row.html.erb`:

```erb
<%= tag.div id: dom_id(conversation) do %>
  <%= render ConversationListRowComponent.new(conversation: conversation, active: false) %>
<% end %>
```

And `_timeline_message.html.erb`:

```erb
<%= tag.div id: dom_id(message) do %>
  <%= render TimelineMessageComponent.new(message: message) %>
<% end %>
```

- [ ] **Step 3: Verify pass**

Run: `bundle exec rspec spec/services/conversations/broadcasts_spec.rb`
Expected: green.

- [ ] **Step 4: Commit**

```bash
git add packages/app/app/services/conversations/broadcasts.rb \
        packages/app/app/views/dashboard/conversations/_list_row.html.erb \
        packages/app/app/views/dashboard/conversations/_timeline_message.html.erb \
        packages/app/spec/services/conversations/broadcasts_spec.rb
git commit -m "feat(broadcasts): central Conversations::Broadcasts module"
```

---

## Task 2: `ConversationStreamsChannel`

**Files:**
- Create: `packages/app/app/channels/conversation_streams_channel.rb`
- Test: `packages/app/spec/channels/conversation_streams_channel_spec.rb`

- [ ] **Step 1: Failing spec**

```ruby
require "rails_helper"
RSpec.describe ConversationStreamsChannel, type: :channel do
  let(:team)  { create(:team) }
  let(:channel) { create(:channel).tap { |c| ChannelTeam.create!(channel: c, team: team) } }
  let(:user)  { create(:user).tap { |u| TeamMember.create!(user: u, team: team) } }

  before { stub_connection current_user: user }

  it "subscribes to personal + channel streams" do
    subscribe(signed_stream_name: Turbo::StreamsChannel.signed_stream_name("conversations:user:#{user.id}"))
    expect(subscription).to be_confirmed
  end

  it "rejects subscription to a channel the user's teams don't attend" do
    foreign = create(:channel)
    subscribe(signed_stream_name: Turbo::StreamsChannel.signed_stream_name("conversations:channel:#{foreign.id}"))
    expect(subscription).to be_rejected
  end

  it "accepts subscription to an accessible channel" do
    subscribe(signed_stream_name: Turbo::StreamsChannel.signed_stream_name("conversations:channel:#{channel.id}"))
    expect(subscription).to be_confirmed
  end
end
```

- [ ] **Step 2: Implement**

```ruby
class ConversationStreamsChannel < Turbo::StreamsChannel
  def subscribed
    name = verified_stream_name_from_params
    return reject unless name && allowed?(name)
    stream_from name
  end

  private

  def allowed?(name)
    case name
    when /\Aconversation:(\d+)\z/
      conv = Conversation.find_by(id: $1)
      conv && ConversationPolicy.new(current_user, conv).can_view?
    when /\Aconversations:user:(\d+)\z/
      $1.to_i == current_user.id
    when /\Aconversations:channel:(\d+)\z/
      user_channel_ids.include?($1.to_i)
    else
      false
    end
  end

  def user_channel_ids
    @user_channel_ids ||= current_user.teams.joins(:channel_teams).pluck("channel_teams.channel_id").uniq
  end
end
```

Then in `config/cable.rb` or wherever the routing for Turbo streams is wired, point `Turbo::StreamsChannel` requests at this subclass — or simpler, monkey-include the gating into `Turbo::StreamsChannel.subscribed` via a Rails initializer:

```ruby
# config/initializers/turbo_stream_gating.rb
Rails.application.config.to_prepare do
  Turbo::StreamsChannel.module_eval do
    alias_method :subscribed_without_gating, :subscribed unless method_defined?(:subscribed_without_gating)
    define_method(:subscribed) do
      name = verified_stream_name_from_params
      return reject unless name && ConversationStreamGate.allowed?(connection.current_user, name)
      stream_from name
    end
  end
end
```

(With a small `ConversationStreamGate` PORO holding the logic; this avoids fighting Turbo's own subclass.) Pick whichever variant is easier to test in the codebase as-is — both are acceptable.

- [ ] **Step 3: Make sure `ApplicationCable::Connection` sets `current_user`** from the session cookie (Spec 02 / 03 likely already did; verify):

```ruby
module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user
    def connect
      self.current_user = find_user_from_session || reject_unauthorized_connection
    end
    # find_user_from_session implementation based on Spec 02 session model
  end
end
```

- [ ] **Step 4: Pass + commit**

```bash
git add packages/app/app/channels/conversation_streams_channel.rb \
        packages/app/config/initializers/turbo_stream_gating.rb \
        packages/app/spec/channels/conversation_streams_channel_spec.rb
git commit -m "feat(realtime): per-user stream gating for Turbo subscriptions"
```

---

## Task 3: Replace placeholders in services

For each service, change one line and re-run its spec. Each gets its own commit.

### 3a — `Assignments::AutoAssign`

Replace `def broadcast_assignment ; nil ; end` with:

```ruby
def broadcast_assignment
  Conversations::Broadcasts.assigned(@conversation)
end
```

Run `bundle exec rspec spec/services/assignments/auto_assign_spec.rb` and verify it still passes (add a `have_broadcasted_to` assertion if 06a's spec didn't include one).

Commit: `feat(realtime): AutoAssign broadcasts via Conversations::Broadcasts`.

### 3b — `Assignments::Transfer`

Replace `broadcast_transfer(_, _)` body with:

```ruby
def broadcast_transfer(from_user_id, _from_team_id)
  Conversations::Broadcasts.transferred(@conversation, from_user_id: from_user_id, from_team_id: nil)
end
```

Run the transfer spec. Commit: `feat(realtime): Transfer broadcasts via Conversations::Broadcasts`.

### 3c — `Conversations::Resolve`

Append after `Events::Emit.call(...)`:

```ruby
Conversations::Broadcasts.resolved(conversation)
```

Commit: `feat(realtime): Resolve broadcasts via Conversations::Broadcasts`.

### 3d — `Ingestion::ProcessMessage` + `ProcessStatusUpdate`

In `ProcessMessage`, after `Messages::Create.call(...)` returns the new inbound message, call:

```ruby
Conversations::Broadcasts.message_appended(message)
```

In `ProcessStatusUpdate`, after updating the message status, call:

```ruby
Conversations::Broadcasts.message_status_changed(message)
```

These replace whatever ad-hoc broadcast code Spec 05 wired (likely `broadcast_replace_later_to` calls scattered in services). Centralize them.

Commit: `refactor(ingestion): use Conversations::Broadcasts for inbound + status broadcasts`.

### 3e — `SendMessageJob`

Replace the `broadcast_status` placeholder from Plan 05a:

```ruby
def broadcast_status(message)
  Conversations::Broadcasts.message_status_changed(message)
end
```

Commit: `feat(realtime): SendMessageJob broadcasts status via Conversations::Broadcasts`.

---

## Task 4: Layout subscriptions

**Files:**
- Modify: `packages/app/app/views/layouts/application.html.erb` (or `dashboard.html.erb` if a separate layout exists)

- [ ] **Step 1: Add subscriptions inside `<body>`, before the workspace renders**

```erb
<% if Current.user %>
  <%= turbo_stream_from "conversations:user:#{Current.user.id}" %>
  <% Current.user.teams.joins(:channel_teams).pluck("channel_teams.channel_id").uniq.each do |cid| %>
    <%= turbo_stream_from "conversations:channel:#{cid}" %>
  <% end %>
<% end %>
```

The active conversation's per-conversation stream (`conversation:#{id}`) is rendered by the `_conversation_detail` partial inside the center pane so it auto-tears-down when the agent navigates away.

In `_conversation_detail.html.erb` add at the top:

```erb
<%= turbo_stream_from "conversation:#{conversation.id}" %>
```

- [ ] **Step 2: Commit**

```bash
git add packages/app/app/views/layouts/application.html.erb \
        packages/app/app/views/dashboard/conversations/_conversation_detail.html.erb
git commit -m "feat(realtime): subscribe dashboard to personal + per-channel + per-conversation streams"
```

---

## Task 5: Integration / system spec

**Files:**
- Create: `packages/app/spec/system/realtime_workspace_spec.rb`

If the harness has Playwright wired (per Spec 01), write a real end-to-end spec:

```ruby
require "rails_helper"
RSpec.describe "Realtime workspace", type: :system do
  it "new inbound message reorders the list for the receiving agent" do
    # Two browser sessions: agent_a logged in viewing /dashboard; trigger an inbound via the meta-stub simulator endpoint;
    # assert the row appears at the top of agent_a's list without a page reload.
    skip "Playwright system spec — uncomment once the test harness from Spec 01 is wired here"
  end
end
```

If Playwright is not yet wired, write a request-level integration spec asserting the broadcast call:

```ruby
require "rails_helper"
RSpec.describe "Realtime workspace integration", type: :request do
  include ActionCable::TestHelper

  let(:team) { create(:team) }
  let(:channel) { create(:channel).tap { |c| ChannelTeam.create!(channel: c, team: team) } }
  let(:agent)   { create(:user, role: "agent").tap { |u| TeamMember.create!(user: u, team: team) } }
  let(:conv)    { create(:conversation, channel: channel, status: "queued") }

  it "inbound message broadcasts to the channel stream the agent subscribes to" do
    msg = create(:message, conversation: conv, direction: "inbound", content: "yo")
    expect { Conversations::Broadcasts.message_appended(msg) }
      .to have_broadcasted_to("conversations:channel:#{channel.id}")
  end
end
```

Commit: `test(realtime): integration coverage for broadcast routing`.

---

## Task 6: Regression + PROGRESS

- [ ] **Step 1: Full suite + standardrb**

Run: `bundle exec rspec && bin/standardrb --fix`
Expected: green.

- [ ] **Step 2: Manual smoke (two browsers)**

Boot the app. Browser A: login as agent on team X. Browser B: separate session, send an inbound via the `meta-stub` simulator targeting a channel in team X. Verify Browser A's list updates without reload. Pickup the conversation from Browser A; verify the row moves to "Mine". Transfer to another agent (use a third browser or the admin's session); verify it disappears from A's "Mine" and appears in the receiver's.

- [ ] **Step 3: Update `docs/PROGRESS.md`** — add 06f row. When this plan ships, every plan under Spec 06 is Shipped → flip Spec 06 to Shipped.

- [ ] **Step 4: PR**

```bash
git push -u origin plan-06f-realtime-scoping
gh pr create --title "Plan 06f: Real-time scoping (Solid Cable)" \
             --body-file docs/plans/06f-2026-05-11-realtime-scoping.md
```

After merge, flip 06f → Shipped and Spec 06 → Shipped in a follow-up doc commit.

---

You can now run `/clear`. Spec 06 complete; next is Spec 07 (Flow Engine).
