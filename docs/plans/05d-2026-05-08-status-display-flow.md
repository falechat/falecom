# Plan 05d: Status Display + Status Update Flow

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> **Spec:** [05 — Outbound Dispatch](../specs/05-outbound-dispatch.md)
> **Date:** 2026-05-08
> **Status:** Draft — awaiting approval
> **Branch:** `plan-05d-status-display-flow`

**Goal:** Close the outbound loop visually: real-time delivery status (pending → sent → delivered → read, plus failed) shown as checkmark icons in the dashboard, updated via Turbo Stream broadcasts whenever a `Message` row's status changes. Backed by status progression rules in `Ingestion::ProcessStatusUpdate` so out-of-order webhooks (e.g., `delivered` after `read`) never regress the displayed state. After this plan, an agent sees their outbound message change from a clock icon to a single grey check, then double grey checks, then double blue checks, all without reloading the page; failed messages show a red icon with the error text on hover.

**Architecture:** `Message.after_update_commit { broadcast_replace_to ... }` (Turbo Streams) replaces the `#message-<id>` element whenever the row changes. `MessageComponent` (created in 05c) gains real status icons via a small `StatusIndicatorComponent`. `Ingestion::ProcessStatusUpdate` (Spec 04) is extended with a status progression guard: `pending < sent < delivered < read`; `failed` always wins; lower-or-equal arrivals are no-ops. `SendMessageJob`'s placeholder `broadcast_status` from Plan 05a becomes redundant once the model-level callback exists — remove it.

**Tech Stack:** Rails 8.1.3, Turbo Streams (model-level broadcasts), ViewComponent, Tailwind 4 + Heroicons (already vendored via JR Components), RSpec, Cuprite for system specs, Playwright for the full inbound-status-webhook → checkmark e2e (per CLAUDE.md "if the change affects the dashboard UI, an end-to-end Playwright test is also mandatory").

---

## Files to touch

### Create

- `packages/app/app/components/status_indicator_component.rb`
- `packages/app/app/components/status_indicator_component.html.erb`
- `packages/app/spec/components/status_indicator_component_spec.rb`
- `packages/app/spec/services/ingestion/process_status_update_progression_spec.rb` — focused additions; the existing spec from Plan 04 stays.
- `packages/app/spec/system/dashboard/status_updates_spec.rb`
- `packages/app/spec/playwright/outbound_status_e2e.spec.ts` — Playwright e2e
- `packages/app/playwright.config.ts` — if not already in repo (Spec 01 may have skipped it)

### Modify

- `packages/app/app/models/message.rb` — `broadcasts_refreshes` or `after_update_commit { broadcast_replace_to ... }` to broadcast status changes.
- `packages/app/app/components/message_component.html.erb` — render `StatusIndicatorComponent` instead of the placeholder text.
- `packages/app/app/services/ingestion/process_status_update.rb` — add progression guard.
- `packages/app/app/jobs/send_message_job.rb` — drop `broadcast_status` placeholder; the model callback handles it.

---

## Order of operations (TDD wave)

1. **`StatusIndicatorComponent`** — pure render component, 5 status branches.
2. **`Message` broadcast on update** — model spec asserts a Turbo Stream message is broadcast when status changes.
3. **`MessageComponent` integration** — replace placeholder with the new component.
4. **Status progression guard** — service spec covering each transition matrix cell, then implement.
5. **System spec** — Cuprite-driven: simulate a status webhook arriving (call the service directly), assert the DOM updates.
6. **Playwright e2e** — drive a real browser through agent reply → status webhook → checkmarks.
7. **Cleanup** — remove the `broadcast_status` placeholder in `SendMessageJob`.
8. **Regression sweep** — full rspec + standardrb + Playwright.

---

## What could go wrong

**Most likely:** `broadcast_replace_to` targets the wrong stream and updates never reach the page. Mitigation: assert in a model spec that the broadcast goes to a specific stream name (`"conversation_#{conversation_id}_messages"`) and that the page subscribes via `<%= turbo_stream_from "conversation_#{@conversation.id}_messages" %>` in `show.html.erb`. The system spec catches drift between sender + subscriber.

**Least likely:** the Cable adapter (Solid Cable, per Spec 01) does not deliver in test mode. Solid Cable test mode supports inline delivery; confirm `config.action_cable.adapter = :solid_cable` in `config/environments/test.rb` and that the Action Cable test helpers are loaded in `rails_helper.rb`.

---

## Task 1: `StatusIndicatorComponent`

**Files:**
- Create: `packages/app/app/components/status_indicator_component.rb` + `.html.erb`
- Test: `packages/app/spec/components/status_indicator_component_spec.rb`

- [ ] **Step 1: Spec**

```ruby
require "rails_helper"

RSpec.describe StatusIndicatorComponent, type: :component do
  {
    "pending"   => {icon: "clock",         color: "text-gray-400"},
    "sent"      => {icon: "check",         color: "text-gray-400"},
    "delivered" => {icon: "check-double",  color: "text-gray-400"},
    "read"      => {icon: "check-double",  color: "text-blue-500"},
    "failed"    => {icon: "exclamation",   color: "text-red-500"}
  }.each do |status, expected|
    it "renders #{status} with #{expected[:icon]} / #{expected[:color]}" do
      msg = build_stubbed(:message, status: status, error: (status == "failed") ? "boom" : nil)
      render_inline(described_class.new(message: msg))
      expect(page).to have_css(".#{expected[:color].tr(' ', '.')}")
      expect(page).to have_css("[data-icon='#{expected[:icon]}']")
    end
  end

  it "shows error message in title for failed" do
    msg = build_stubbed(:message, status: "failed", error: "rate limit")
    render_inline(described_class.new(message: msg))
    expect(page).to have_css("[title='rate limit']")
  end
end
```

- [ ] **Step 2: Implement**

```ruby
class StatusIndicatorComponent < ViewComponent::Base
  ICONS = {
    "pending" => {icon: "clock", color: "text-gray-400"},
    "sent" => {icon: "check", color: "text-gray-400"},
    "delivered" => {icon: "check-double", color: "text-gray-400"},
    "read" => {icon: "check-double", color: "text-blue-500"},
    "failed" => {icon: "exclamation", color: "text-red-500"}
  }.freeze

  def initialize(message:)
    @message = message
    @config = ICONS.fetch(@message.status)
  end

  attr_reader :message, :config
end
```

```erb
<span class="<%= config[:color] %> inline-flex items-center"
      data-icon="<%= config[:icon] %>"
      title="<%= message.error if message.failed? %>">
  <%= heroicon_for(config[:icon]) %>
</span>
```

(`heroicon_for` is whatever icon helper the app already uses — probably from JR Components. If absent, drop in raw SVGs from heroicons.com keyed by name; keep the helper local to this component.)

- [ ] **Step 3: Run, verify pass, commit**

```bash
bundle exec rspec spec/components/status_indicator_component_spec.rb
git add packages/app/app/components/status_indicator_component* \
        packages/app/spec/components/status_indicator_component_spec.rb
git commit -m "feat(components): add StatusIndicatorComponent for outbound message statuses"
```

---

## Task 2: `Message` broadcasts on update

**Files:**
- Modify: `packages/app/app/models/message.rb`

- [ ] **Step 1: Spec**

`packages/app/spec/models/message_spec.rb`:

```ruby
describe "Turbo broadcast on status change" do
  let(:conversation) { create(:conversation) }
  let(:message) { create(:message, conversation: conversation, channel: conversation.channel, direction: "outbound", status: "pending") }

  it "broadcasts a replace to the conversation stream when status changes" do
    expect {
      message.update!(status: "sent")
    }.to have_broadcasted_to("conversation_#{conversation.id}_messages")
      .with(a_string_including("message-#{message.id}"))
  end

  it "does not broadcast when an unrelated attribute changes" do
    expect {
      message.update!(metadata: {"x" => 1})
    }.not_to have_broadcasted_to("conversation_#{conversation.id}_messages")
  end
end
```

- [ ] **Step 2: Implement**

```ruby
class Message < ApplicationRecord
  # ... existing code ...

  after_update_commit :broadcast_status_change, if: :saved_change_to_status?

  private

  def broadcast_status_change
    broadcast_replace_to(
      "conversation_#{conversation_id}_messages",
      target: "message-#{id}",
      partial: "dashboard/messages/message",
      locals: {message: self}
    )
  end
end
```

(Use a partial that wraps `MessageComponent` so the broadcast renders the same DOM the initial page renders. Add `packages/app/app/views/dashboard/messages/_message.html.erb` with `<%= render(MessageComponent.new(message: message)) %>`.)

- [ ] **Step 3: Verify spec passes, commit**

```bash
git add packages/app/app/models/message.rb \
        packages/app/app/views/dashboard/messages/_message.html.erb \
        packages/app/spec/models/message_spec.rb
git commit -m "feat(message): broadcast Turbo Stream replace on status change"
```

---

## Task 3: Subscribe the page

**Files:**
- Modify: `packages/app/app/views/dashboard/conversations/show.html.erb`

- [ ] **Step 1: Add the stream subscription at the top of the view**

```erb
<%= turbo_stream_from "conversation_#{@conversation.id}_messages" %>
```

- [ ] **Step 2: Replace the placeholder status text in `MessageComponent` with the new component**

In `app/components/message_component.html.erb`, replace `<%= status_indicator %>` with:

```erb
<% if @message.outbound? %>
  <%= render(StatusIndicatorComponent.new(message: @message)) %>
<% end %>
```

Drop the `status_indicator` method from `MessageComponent`.

- [ ] **Step 3: Update component spec from Plan 05c to expect the new icon**

In `spec/components/message_component_spec.rb`, change the outbound assertion from `have_css(".status-indicator", text: "pending")` to `have_css("[data-icon='clock']")`.

- [ ] **Step 4: Verify, commit**

```bash
bundle exec rspec spec/components
git add packages/app/app/components/message_component* \
        packages/app/app/views/dashboard/conversations/show.html.erb \
        packages/app/spec/components/message_component_spec.rb
git commit -m "feat(dashboard): subscribe show page to message status stream"
```

---

## Task 4: Status progression guard

**Files:**
- Modify: `packages/app/app/services/ingestion/process_status_update.rb`
- Create: `packages/app/spec/services/ingestion/process_status_update_progression_spec.rb`

- [ ] **Step 1: Spec the matrix**

```ruby
require "rails_helper"

RSpec.describe Ingestion::ProcessStatusUpdate do
  let(:channel) { create(:channel) }
  let(:message) { create(:message, channel: channel, direction: "outbound", external_id: "ext-1", status: initial_status) }

  describe "progression rules" do
    progression = %w[pending sent delivered read]

    progression.each_with_index do |from, i|
      progression.each_with_index do |to, j|
        context "from #{from} to #{to}" do
          let(:initial_status) { from }

          if j > i
            it "advances to #{to}" do
              described_class.call(payload_for(message, to))
              expect(message.reload.status).to eq(to)
            end
          else
            it "is a no-op (no regression)" do
              described_class.call(payload_for(message, to))
              expect(message.reload.status).to eq(from)
            end
          end
        end
      end
    end

    it "failed always wins from any state" do
      ["pending", "sent", "delivered", "read"].each do |s|
        m = create(:message, channel: channel, direction: "outbound", external_id: "ext-#{s}", status: s)
        described_class.call(payload_for(m, "failed"))
        expect(m.reload.status).to eq("failed")
      end
    end

    it "no status overrides failed" do
      m = create(:message, channel: channel, direction: "outbound", external_id: "ext-x", status: "failed")
      described_class.call(payload_for(m, "delivered"))
      expect(m.reload.status).to eq("failed")
    end
  end

  def payload_for(message, status)
    {
      "type" => "outbound_status_update",
      "channel" => {"type" => message.channel.channel_type, "identifier" => message.channel.identifier},
      "message" => {"external_id" => message.external_id, "status" => status, "occurred_at" => Time.current.iso8601}
    }
  end
end
```

- [ ] **Step 2: Implement guard**

In `app/services/ingestion/process_status_update.rb`, replace the unconditional `update!` with:

```ruby
ORDER = {"pending" => 0, "sent" => 1, "delivered" => 2, "read" => 3}.freeze

def self.call(payload)
  external_id = payload.dig("message", "external_id")
  new_status = payload.dig("message", "status")
  message = Message.find_by(external_id: external_id)
  return nil unless message

  return message if message.status == "failed"
  if new_status == "failed"
    message.update!(status: "failed")
    return message
  end

  current_rank = ORDER.fetch(message.status, -1)
  new_rank = ORDER.fetch(new_status, -1)
  return message if new_rank <= current_rank

  message.update!(status: new_status)
  message
end
```

(Adapt to whatever existing shape the service has — preserve event emission and any current logging. The progression check is the new piece.)

- [ ] **Step 3: Verify all matrix specs pass, plus the existing 04 specs still green**

```bash
bundle exec rspec spec/services/ingestion
```

- [ ] **Step 4: Commit**

```bash
git add packages/app/app/services/ingestion/process_status_update.rb \
        packages/app/spec/services/ingestion/process_status_update_progression_spec.rb
git commit -m "feat(ingestion): enforce monotonic status progression with failed-wins"
```

---

## Task 5: System spec — checkmarks update live

**Files:**
- Create: `packages/app/spec/system/dashboard/status_updates_spec.rb`

- [ ] **Step 1: Spec**

```ruby
require "rails_helper"

RSpec.describe "Outbound status updates", type: :system do
  let(:agent) { create(:user) }
  let(:channel) { create(:channel) }
  let(:conversation) { create(:conversation, channel: channel, assignee: agent) }
  let!(:message) do
    create(:message, channel: channel, conversation: conversation,
                     direction: "outbound", status: "pending",
                     external_id: "ext-1", content: "hi")
  end

  before do
    driven_by(:cuprite)
    login_as(agent)
  end

  it "updates the icon as status webhooks arrive" do
    visit dashboard_conversation_path(conversation)
    expect(page).to have_css("#message-#{message.id} [data-icon='clock']")

    Ingestion::ProcessStatusUpdate.call(payload_for(message, "sent"))
    expect(page).to have_css("#message-#{message.id} [data-icon='check']")

    Ingestion::ProcessStatusUpdate.call(payload_for(message, "delivered"))
    expect(page).to have_css("#message-#{message.id} [data-icon='check-double'].text-gray-400")

    Ingestion::ProcessStatusUpdate.call(payload_for(message, "read"))
    expect(page).to have_css("#message-#{message.id} [data-icon='check-double'].text-blue-500")
  end

  def payload_for(message, status)
    {
      "type" => "outbound_status_update",
      "channel" => {"type" => message.channel.channel_type, "identifier" => message.channel.identifier},
      "message" => {"external_id" => message.external_id, "status" => status, "occurred_at" => Time.current.iso8601}
    }
  end
end
```

- [ ] **Step 2: Run, fix any selector mismatches**

```bash
bundle exec rspec spec/system/dashboard/status_updates_spec.rb
```

- [ ] **Step 3: Commit**

```bash
git add packages/app/spec/system/dashboard/status_updates_spec.rb
git commit -m "test(system): live status checkmark updates via Turbo Stream"
```

---

## Task 6: Playwright e2e — full reply + status round-trip

**Files:**
- Create: `packages/app/spec/playwright/outbound_status_e2e.spec.ts`
- Modify or create: `packages/app/playwright.config.ts`

- [ ] **Step 1: Bootstrap Playwright in `packages/app`** (only if not done in Spec 01 — check `package.json`)

```bash
cd packages/app
npx playwright install chromium
```

Add `playwright.config.ts` with `baseURL: process.env.PLAYWRIGHT_BASE_URL || "http://localhost:3000"`, `webServer: { command: "bin/rails server -e test", port: 3000 }`.

- [ ] **Step 2: Spec**

```ts
import { test, expect } from "@playwright/test";

test("outbound reply progresses through status checkmarks", async ({ page, request }) => {
  // Test seed creates an agent + conversation; details depend on how Spec 01
  // wired test data setup. Assume a /test/seed endpoint is available in test env.
  const seed = await request.post("/test/seed/outbound_scenario").then(r => r.json());

  await page.goto(`/dashboard/conversations/${seed.conversation_id}`);
  await page.fill("textarea[name='message[content]']", "Hello e2e");
  await page.click("button:has-text('Send')");

  const message = page.locator(`article:has-text('Hello e2e')`);
  await expect(message.locator("[data-icon='clock']")).toBeVisible();

  // Simulate provider status webhooks via /test/simulate_status
  await request.post("/test/simulate_status", {data: {external_id: seed.external_id, status: "sent"}});
  await expect(message.locator("[data-icon='check']")).toBeVisible();

  await request.post("/test/simulate_status", {data: {external_id: seed.external_id, status: "delivered"}});
  await expect(message.locator("[data-icon='check-double']")).toHaveClass(/text-gray-400/);

  await request.post("/test/simulate_status", {data: {external_id: seed.external_id, status: "read"}});
  await expect(message.locator("[data-icon='check-double']")).toHaveClass(/text-blue-500/);
});
```

- [ ] **Step 3: Add the `/test/seed` and `/test/simulate_status` test-only routes**

Guard with `Rails.env.test?` and route them to a `Test::HarnessController` that creates the fixtures via the same paths the app uses (no factories shortcuts — per CLAUDE.md "Never use fixtures in end-to-end tests"). For status simulation, call `Ingestion::ProcessStatusUpdate.call(...)` directly. The controller exists only in `Rails.env.test?`.

- [ ] **Step 4: Run**

```bash
bin/rails server -e test &
PLAYWRIGHT_BASE_URL=http://localhost:3000 npx playwright test spec/playwright/outbound_status_e2e.spec.ts
```

Expected: green.

- [ ] **Step 5: Commit**

```bash
git add packages/app/spec/playwright \
        packages/app/playwright.config.ts \
        packages/app/app/controllers/test
git commit -m "test(e2e): Playwright outbound reply -> checkmarks progression"
```

---

## Task 7: Cleanup `SendMessageJob`

**Files:**
- Modify: `packages/app/app/jobs/send_message_job.rb`

- [ ] **Step 1: Drop the placeholder `broadcast_status` private method**

The `Message` model now broadcasts on `saved_change_to_status?`, which fires on every `update!(status: ...)` inside the job. The job's placeholder is redundant.

- [ ] **Step 2: Update the job spec**

Remove any assertions about the placeholder. The existing model-level broadcast spec (Task 2) covers the broadcast path.

- [ ] **Step 3: Run job specs, verify pass**

```bash
bundle exec rspec spec/jobs/send_message_job_spec.rb
```

- [ ] **Step 4: Commit**

```bash
git add packages/app/app/jobs/send_message_job.rb packages/app/spec/jobs/send_message_job_spec.rb
git commit -m "refactor(jobs): drop SendMessageJob#broadcast_status; model callback covers it"
```

---

## Task 8: Regression sweep + PROGRESS.md + spec close-out

- [ ] **Step 1: All test suites**

```bash
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && bundle exec rspec"
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && PLAYWRIGHT_BASE_URL=http://localhost:3000 npx playwright test"
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/channels/whatsapp-cloud && bundle exec rspec"
```

- [ ] **Step 2: standardrb**

```bash
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && bin/standardrb --fix"
```

- [ ] **Step 3: Update `docs/PROGRESS.md`**

Mark Plan 05d as **In Progress** before merging the PR; on merge, flip 05a/05b/05c/05d all to **Shipped** and Spec 05 to **Shipped**.

- [ ] **Step 4: Update `ARCHITECTURE.md`** — confirm the Outbound Message Flow section still matches reality. Add a one-liner about the model-level Turbo broadcast for status changes if not already documented.

- [ ] **Step 5: PR**

```bash
git push -u origin plan-05d-status-display-flow
gh pr create --title "Plan 05d: Status indicator + progression + e2e" --body-file docs/plans/05d-2026-05-08-status-display-flow.md
```
