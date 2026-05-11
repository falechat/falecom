# Plan 06d: Conversation Timeline + Content-Type Rendering

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans`.
> **Spec:** [06 — Assignment, Transfer & Workspace](../specs/06-assignment-transfer-workspace.md)
> **Date:** 2026-05-11
> **Status:** Draft — awaiting approval
> **Branch:** `plan-06d-conversation-timeline`
> **Depends on:** Plan 06c (renders inside the center pane).

**Goal:** Replace the bare messages list in the conversation detail with a `ConversationTimelineComponent` that interleaves `Message`s and `Event`s in chronological order, plus per-`content_type` renderers for `text`, `image`, `audio`, `video`, `document`, `location`, `contact_card`. Render system messages (sender: nil) and the `flows:handoff` / `conversations:transferred` events as centered pills. After this plan, an agent reading a conversation sees the full audit story, not just the messages.

**Architecture:** A `ConversationTimelineComponent` takes a conversation and builds an ordered list of `TimelineItem` value objects (a struct around either a Message or an Event with a `kind` and `created_at`). The component delegates rendering to per-kind sub-components (`TimelineMessageComponent`, `TimelineEventComponent`, `TimelineSystemMessageComponent`). `TimelineMessageComponent` itself dispatches on `content_type` to small partials — keeping each content-type renderer in its own file avoids one fat conditional. Metadata fields the renderers read from: `metadata["caption"]` (image/video), `metadata["filename"]` and `metadata["size"]` (document), `metadata["latitude"]`/`metadata["longitude"]` (location), `metadata["vcard"]` (contact_card). Attachments use Active Storage blobs already wired in Spec 02.

**Tech Stack:** Ruby 4.0.2, Rails 8.1.3, ViewComponent, Tailwind. No new gems. `audio_tag`/`video_tag` Rails helpers cover players.

---

## Files to touch

### Create

- `packages/app/app/components/conversation_timeline_component.rb`
- `packages/app/app/components/conversation_timeline_component.html.erb`
- `packages/app/app/components/timeline_message_component.rb`
- `packages/app/app/components/timeline_message_component.html.erb`
- `packages/app/app/components/timeline_event_component.rb`
- `packages/app/app/components/timeline_event_component.html.erb`
- `packages/app/app/components/timeline_system_message_component.rb`
- `packages/app/app/components/timeline_system_message_component.html.erb`
- `packages/app/app/components/timeline/text_component.html.erb`
- `packages/app/app/components/timeline/image_component.html.erb`
- `packages/app/app/components/timeline/audio_component.html.erb`
- `packages/app/app/components/timeline/video_component.html.erb`
- `packages/app/app/components/timeline/document_component.html.erb`
- `packages/app/app/components/timeline/location_component.html.erb`
- `packages/app/app/components/timeline/contact_card_component.html.erb`
- `packages/app/app/components/timeline/text_component.rb` … (one `.rb` per partial; all share a tiny `Timeline::ContentTypeBase` superclass)

### Modify

- `packages/app/app/views/dashboard/conversations/_conversation_detail.html.erb` — replace the messages list with `ConversationTimelineComponent`.

### Tests

- `packages/app/spec/components/conversation_timeline_component_spec.rb`
- `packages/app/spec/components/timeline_message_component_spec.rb`
- `packages/app/spec/components/timeline_event_component_spec.rb`
- `packages/app/spec/components/timeline/image_component_spec.rb` (one per non-text content type; text is covered in the message spec)

---

## Order of operations

1. **`ConversationTimelineComponent`** — interleaving logic. Test ordering + filtering.
2. **`TimelineMessageComponent`** — dispatches by `content_type`. Test that each type renders the right partial.
3. **`TimelineSystemMessageComponent`** — centered pill for `sender: nil` messages.
4. **`TimelineEventComponent`** — renders specific event names with friendly labels.
5. **Per-content-type partials** (text, image, audio, video, document, location, contact_card). One commit per type with a focused spec.
6. **Wire into `_conversation_detail.html.erb`.**
7. **Regression + PROGRESS.**

---

## What could go wrong

**Most likely:** mismatched ordering when a `Message` and `Event` share an exact `created_at` timestamp — Postgres returns them in arbitrary order. Mitigation: secondary sort by class name (`Message` before `Event` of the same timestamp keeps the conversation flow readable) and tertiary by id.

**Least likely:** ActiveStorage attachment URL generation needs the host config. Spec 02 already sets `Rails.application.routes.default_url_options[:host]` in dev/test; verify.

---

## Task 1: `ConversationTimelineComponent`

**Files:**
- Create: `packages/app/app/components/conversation_timeline_component.rb`
- Create: `packages/app/app/components/conversation_timeline_component.html.erb`
- Test: `packages/app/spec/components/conversation_timeline_component_spec.rb`

- [ ] **Step 1: Failing spec**

```ruby
require "rails_helper"

RSpec.describe ConversationTimelineComponent, type: :component do
  let(:conv) { create(:conversation) }

  it "interleaves messages and events in chronological order" do
    t0 = 1.hour.ago
    m1 = create(:message, conversation: conv, content: "hi", created_at: t0)
    Event.create!(name: "conversations:assigned", subject: conv, payload: {}, created_at: t0 + 1.minute)
    m2 = create(:message, conversation: conv, content: "back at you", created_at: t0 + 2.minutes)

    html = render_inline(described_class.new(conversation: conv))
    text = html.text.gsub(/\s+/, " ")
    expect(text.index("hi")).to be < text.index("conversations:assigned")
    expect(text.index("conversations:assigned")).to be < text.index("back at you")
  end

  it "filters out events not in the whitelist (noise reduction)" do
    Event.create!(name: "messages:inbound", subject: conv, payload: {})
    html = render_inline(described_class.new(conversation: conv))
    expect(html.text).not_to include("messages:inbound")
  end
end
```

- [ ] **Step 2: Implement**

```ruby
class ConversationTimelineComponent < ViewComponent::Base
  EVENT_WHITELIST = %w[
    conversations:assigned
    conversations:transferred
    conversations:resolved
    flows:handoff
    users:availability_changed
  ].freeze

  def initialize(conversation:)
    @conversation = conversation
  end

  def items
    messages = @conversation.messages.includes(:sender).to_a
    events = Event.where(subject: @conversation, name: EVENT_WHITELIST).to_a
    (messages + events).sort_by { |i| [i.created_at, i.is_a?(Message) ? 0 : 1, i.id] }
  end
end
```

```erb
<div class="flex-1 overflow-y-auto p-4 space-y-2 bg-gray-50">
  <% items.each do |item| %>
    <% if item.is_a?(Message) %>
      <% if item.sender.nil? && item.direction == "outbound" %>
        <%= render TimelineSystemMessageComponent.new(message: item) %>
      <% else %>
        <%= render TimelineMessageComponent.new(message: item) %>
      <% end %>
    <% else %>
      <%= render TimelineEventComponent.new(event: item) %>
    <% end %>
  <% end %>
</div>
```

- [ ] **Step 3: Pass + commit**

```bash
git add packages/app/app/components/conversation_timeline_component* \
        packages/app/spec/components/conversation_timeline_component_spec.rb
git commit -m "feat(components): ConversationTimelineComponent with interleaved messages + events"
```

---

## Task 2: `TimelineMessageComponent` (text + dispatch)

**Files:**
- Create: `packages/app/app/components/timeline_message_component.rb`
- Create: `packages/app/app/components/timeline_message_component.html.erb`
- Create: `packages/app/app/components/timeline/text_component.rb` + `.html.erb`
- Test: `packages/app/spec/components/timeline_message_component_spec.rb`

- [ ] **Step 1: Failing spec**

```ruby
require "rails_helper"
RSpec.describe TimelineMessageComponent, type: :component do
  it "renders inbound text left-aligned" do
    msg = create(:message, direction: "inbound", content: "hi there", content_type: "text")
    html = render_inline(described_class.new(message: msg))
    expect(html.css(".bubble.inbound")).not_to be_empty
    expect(html.text).to include("hi there")
  end

  it "renders outbound text right-aligned with status checkmarks" do
    msg = create(:message, direction: "outbound", content: "yo", content_type: "text", status: "delivered")
    html = render_inline(described_class.new(message: msg))
    expect(html.css(".bubble.outbound")).not_to be_empty
    expect(html.css(".status-delivered")).not_to be_empty
  end

  it "dispatches to image partial for image content_type" do
    msg = create(:message, direction: "inbound", content: nil, content_type: "image", metadata: {"caption" => "look"})
    html = render_inline(described_class.new(message: msg))
    expect(html.css("img, .timeline-image")).not_to be_empty
  end
end
```

- [ ] **Step 2: Implement**

```ruby
class TimelineMessageComponent < ViewComponent::Base
  def initialize(message:)
    @message = message
  end

  def alignment = @message.direction == "outbound" ? "outbound" : "inbound"

  def content_partial
    case @message.content_type
    when "text"         then "timeline/text"
    when "image"        then "timeline/image"
    when "audio"        then "timeline/audio"
    when "video"        then "timeline/video"
    when "document"     then "timeline/document"
    when "location"     then "timeline/location"
    when "contact_card" then "timeline/contact_card"
    else                     "timeline/text"
    end
  end

  def status_icon
    return nil unless @message.direction == "outbound"
    {"pending" => "⏳", "sent" => "✓", "delivered" => "✓✓", "read" => "✓✓ (read)", "failed" => "⚠️"}[@message.status]
  end
end
```

```erb
<div class="flex <%= alignment == "outbound" ? "justify-end" : "justify-start" %>">
  <div class="bubble <%= alignment %> max-w-[70%] rounded-lg px-3 py-2 <%= alignment == "outbound" ? "bg-blue-100" : "bg-white border" %>">
    <%= render partial: content_partial, locals: {message: @message} %>
    <% if status_icon %>
      <div class="text-xs text-gray-500 mt-1 status-<%= @message.status %>"><%= status_icon %> · <%= l(@message.created_at, format: :short) %></div>
    <% else %>
      <div class="text-xs text-gray-500 mt-1"><%= l(@message.created_at, format: :short) %></div>
    <% end %>
  </div>
</div>
```

Text partial — `app/components/timeline/text_component.html.erb`:

```erb
<div class="whitespace-pre-wrap"><%= simple_format(message.content.to_s) %></div>
```

(For partial rendering via `render partial:`, no `.rb` file is required; the `.erb` is enough.)

- [ ] **Step 3: Pass + commit**

```bash
git add packages/app/app/components/timeline_message_component* \
        packages/app/app/components/timeline/text_component.html.erb \
        packages/app/spec/components/timeline_message_component_spec.rb
git commit -m "feat(components): TimelineMessageComponent with text rendering + content_type dispatch"
```

---

## Task 3: `TimelineSystemMessageComponent`

**Files:**
- Create: `packages/app/app/components/timeline_system_message_component.rb`
- Create: `packages/app/app/components/timeline_system_message_component.html.erb`

- [ ] **Step 1: Implement**

```ruby
class TimelineSystemMessageComponent < ViewComponent::Base
  def initialize(message:) ; @message = message ; end
end
```

```erb
<div class="flex justify-center">
  <div class="text-xs text-gray-600 italic px-3 py-1 bg-yellow-50 rounded-full border border-yellow-200">
    <%= @message.content %>
  </div>
</div>
```

- [ ] **Step 2: Commit**

```bash
git add packages/app/app/components/timeline_system_message_component*
git commit -m "feat(components): TimelineSystemMessageComponent (centered pill for system notes)"
```

---

## Task 4: `TimelineEventComponent`

**Files:**
- Create: `packages/app/app/components/timeline_event_component.rb`
- Create: `packages/app/app/components/timeline_event_component.html.erb`
- Test: `packages/app/spec/components/timeline_event_component_spec.rb`

- [ ] **Step 1: Failing spec**

```ruby
require "rails_helper"
RSpec.describe TimelineEventComponent, type: :component do
  let(:conv) { create(:conversation) }

  it "renders 'Assigned to <user>' for conversations:assigned" do
    u = create(:user, name: "Maria")
    e = Event.create!(name: "conversations:assigned", subject: conv, payload: {"assignee_id" => u.id})
    html = render_inline(described_class.new(event: e))
    expect(html.text).to include("Maria")
  end

  it "renders 'Handed off to <team>' for flows:handoff" do
    team = create(:team, name: "Finance")
    e = Event.create!(name: "flows:handoff", subject: conv, payload: {"team_id" => team.id})
    html = render_inline(described_class.new(event: e))
    expect(html.text).to include("Finance")
  end
end
```

- [ ] **Step 2: Implement**

```ruby
class TimelineEventComponent < ViewComponent::Base
  def initialize(event:) ; @event = event ; end

  def label
    case @event.name
    when "conversations:assigned"
      who = User.find_by(id: @event.payload["assignee_id"])&.name || "agent"
      "Assigned to #{who}"
    when "conversations:transferred"
      from = User.find_by(id: @event.payload["from_user_id"])&.name
      to   = User.find_by(id: @event.payload["to_user_id"])&.name
      team = Team.find_by(id: @event.payload["to_team_id"])&.name
      to_label = [to, team].compact.join(" / ").presence || "queued"
      "Transferred #{from ? "from #{from} " : ""}to #{to_label}"
    when "conversations:resolved"
      "Resolved"
    when "flows:handoff"
      team = Team.find_by(id: @event.payload["team_id"])&.name || "team"
      "Bot handed off to #{team}"
    else
      @event.name
    end
  end
end
```

```erb
<div class="flex justify-center">
  <div class="text-xs text-gray-500 px-3 py-1 bg-gray-100 rounded-full">
    <%= label %> · <%= l(@event.created_at, format: :short) %>
  </div>
</div>
```

- [ ] **Step 3: Pass + commit**

```bash
git add packages/app/app/components/timeline_event_component* \
        packages/app/spec/components/timeline_event_component_spec.rb
git commit -m "feat(components): TimelineEventComponent with friendly labels"
```

---

## Task 5: Per-content-type partials

For each non-text type, add the partial + a focused spec asserting it renders the right element. Below: complete content for each partial. Specs follow the same template — replace `image` with the type name, build a message with the right metadata, render via `TimelineMessageComponent`, assert the expected DOM element.

### 5a — image

`app/components/timeline/image_component.html.erb`:

```erb
<% url = message.attachments.first&.then { |a| rails_blob_url(a) } || message.metadata["url"] %>
<% if url %>
  <a href="<%= url %>" target="_blank" class="block">
    <img src="<%= url %>" class="timeline-image rounded max-w-xs object-cover" alt="image">
  </a>
<% end %>
<% if message.metadata["caption"].present? %>
  <div class="text-sm mt-1"><%= message.metadata["caption"] %></div>
<% end %>
```

Spec `spec/components/timeline/image_component_spec.rb`:

```ruby
require "rails_helper"
RSpec.describe "timeline/image partial", type: :component do
  it "renders <img> + caption" do
    msg = create(:message, direction: "inbound", content_type: "image", metadata: {"url" => "https://cdn/x.jpg", "caption" => "look"})
    html = render_inline(TimelineMessageComponent.new(message: msg))
    expect(html.css("img.timeline-image[src='https://cdn/x.jpg']")).not_to be_empty
    expect(html.text).to include("look")
  end
end
```

Commit: `feat(components): timeline image renderer`.

### 5b — audio

`audio_component.html.erb`:

```erb
<% url = message.attachments.first&.then { |a| rails_blob_url(a) } || message.metadata["url"] %>
<%= audio_tag url, controls: true, class: "timeline-audio max-w-xs" if url %>
```

Commit: `feat(components): timeline audio renderer`.

### 5c — video

`video_component.html.erb`:

```erb
<% url = message.attachments.first&.then { |a| rails_blob_url(a) } || message.metadata["url"] %>
<% if url %>
  <%= video_tag url, controls: true, class: "timeline-video max-w-xs rounded" %>
<% end %>
<% if message.metadata["caption"].present? %>
  <div class="text-sm mt-1"><%= message.metadata["caption"] %></div>
<% end %>
```

Commit: `feat(components): timeline video renderer`.

### 5d — document

`document_component.html.erb`:

```erb
<% url = message.attachments.first&.then { |a| rails_blob_url(a) } || message.metadata["url"] %>
<% filename = message.metadata["filename"] || "file" %>
<% size = message.metadata["size"]&.then { |s| number_to_human_size(s) } %>
<% if url %>
  <a href="<%= url %>" target="_blank" class="timeline-document flex items-center gap-2 underline">
    📎 <%= filename %><% if size %> · <%= size %><% end %>
  </a>
<% end %>
```

Commit: `feat(components): timeline document renderer`.

### 5e — location

`location_component.html.erb`:

```erb
<% lat = message.metadata["latitude"]; lng = message.metadata["longitude"] %>
<% if lat && lng %>
  <a class="timeline-location block" href="https://www.openstreetmap.org/?mlat=<%= lat %>&mlon=<%= lng %>#map=15/<%= lat %>/<%= lng %>" target="_blank">
    <img src="https://staticmap.openstreetmap.de/staticmap.php?center=<%= lat %>,<%= lng %>&zoom=15&size=300x180&markers=<%= lat %>,<%= lng %>,red-pushpin" class="rounded" alt="map">
    <div class="text-xs text-gray-600 mt-1">📍 <%= lat %>, <%= lng %></div>
  </a>
<% end %>
```

Commit: `feat(components): timeline location renderer`.

### 5f — contact_card

`contact_card_component.html.erb`:

```erb
<% vcard = message.metadata["vcard"] || {} %>
<div class="timeline-contact-card border rounded p-2">
  <div class="font-medium">👤 <%= vcard["name"] || "Contact" %></div>
  <% if vcard["phone"] %><div class="text-sm text-gray-600"><%= vcard["phone"] %></div><% end %>
  <% if vcard["data"] %>
    <a href="data:text/vcard;base64,<%= Base64.strict_encode64(vcard["data"]) %>" download="<%= vcard["name"] || "contact" %>.vcf" class="text-xs underline">Download .vcf</a>
  <% end %>
</div>
```

Commit: `feat(components): timeline contact_card renderer`.

Each partial gets its own one-it spec verifying the marker class (`timeline-audio`, `timeline-video`, `timeline-document`, `timeline-location`, `timeline-contact-card`) is in the rendered output. Keep them tight — these are mainly smoke tests against the dispatch.

---

## Task 6: Wire into `_conversation_detail.html.erb`

**Files:**
- Modify: `packages/app/app/views/dashboard/conversations/_conversation_detail.html.erb`

- [ ] **Step 1: Replace the old messages list with**

```erb
<header class="border-b p-3 bg-white flex items-center justify-between">
  <div>
    <div class="font-semibold"><%= conversation.contact&.name %></div>
    <div class="text-xs text-gray-500">#<%= conversation.display_id %> · <%= conversation.channel.name %></div>
  </div>
  <%= render "dashboard/conversations/action_bar", conversation: conversation %>
</header>

<%= render ConversationTimelineComponent.new(conversation: conversation) %>

<footer class="border-t p-3 bg-white">
  <%= render "dashboard/conversations/reply_form", conversation: conversation %>
</footer>
```

`_action_bar.html.erb` holds the Pickup / Transfer / Resolve buttons from Plan 06b; if 06b put them inline, move them out into this partial as part of this commit.

- [ ] **Step 2: Manual smoke**

Load a conversation in the dashboard. Verify each rendered content type appears correctly (use the `meta-stub` simulator to inject one of each type if needed).

- [ ] **Step 3: Commit**

```bash
git add packages/app/app/views/dashboard/conversations/_conversation_detail.html.erb \
        packages/app/app/views/dashboard/conversations/_action_bar.html.erb
git commit -m "feat(dashboard): render timeline in conversation detail"
```

---

## Task 7: Regression + PROGRESS

- [ ] **Step 1: Full suite + standardrb**

Run: `bundle exec rspec && bin/standardrb --fix`
Expected: green.

- [ ] **Step 2: Update `docs/PROGRESS.md`** — add 06d row.

- [ ] **Step 3: PR**

```bash
git push -u origin plan-06d-conversation-timeline
gh pr create --title "Plan 06d: Conversation timeline + content-type rendering" \
             --body-file docs/plans/06d-2026-05-11-conversation-timeline.md
```

---

You can now run `/clear` and `/execute-plan docs/plans/06e-2026-05-11-admin-and-contact-mgmt.md`.
