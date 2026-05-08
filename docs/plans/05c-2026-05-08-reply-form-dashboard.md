# Plan 05c: Reply Form — Dashboard Controller + Turbo Frame

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> **Spec:** [05 — Outbound Dispatch](../specs/05-outbound-dispatch.md)
> **Date:** 2026-05-08
> **Status:** Draft — awaiting approval
> **Branch:** `plan-05c-reply-form-dashboard`

**Goal:** Give agents a usable reply form in the conversation detail view. Submit posts to `Dashboard::MessagesController#create`, which calls `Dispatch::Outbound.call(...)` (Plan 05a), and responds with a Turbo Stream that appends the new message and resets the form. Authorization gates access to the conversation. After this plan, an agent can pick a conversation, type, click Send, and immediately see their message in the thread with a `pending` status indicator.

**Architecture:** Standard Rails 8 + Hotwire pattern. `ConversationsController#show` already renders the thread (Spec 02 / dashboard scaffolding); we add the reply form partial inside it as a Turbo Frame. The form `POST`s to `dashboard/conversations/:id/messages`, the controller calls the service, then renders `create.turbo_stream.erb` with a `turbo_stream.append "messages-#{conversation.id}"` and `turbo_stream.replace "reply-form-#{conversation.id}"` (cleared form). Authorization uses the existing `current_user.can_reply_to?(conversation)` predicate; if it doesn't exist on `User`, add it as a thin wrapper around `conversation.assignee_id == current_user.id || current_user.role == "admin"`.

**Tech Stack:** Rails 8.1.3, Turbo Streams, ViewComponent + JR Components, Tailwind 4, Vite. Capybara + Cuprite for system specs (Playwright reserved for full e2e in Plan 05d). No new gems.

---

## Files to touch

### Create

- `packages/app/app/controllers/dashboard/messages_controller.rb`
- `packages/app/app/views/dashboard/messages/create.turbo_stream.erb`
- `packages/app/app/views/dashboard/conversations/_reply_form.html.erb`
- `packages/app/app/components/message_component.rb` — if not present from Spec 02 work
- `packages/app/app/components/message_component.html.erb` — single message renderer reused by append + initial render
- `packages/app/spec/requests/dashboard/messages_spec.rb`
- `packages/app/spec/system/dashboard/reply_flow_spec.rb`

### Modify

- `packages/app/config/routes.rb` — `namespace :dashboard { resources :conversations, only: [...] do; resources :messages, only: [:create]; end }`.
- `packages/app/app/views/dashboard/conversations/show.html.erb` — render `_reply_form` partial inside a Turbo Frame and the messages list inside `#messages-<%= conversation.id %>`.
- `packages/app/app/models/user.rb` — add `can_reply_to?(conversation)` predicate if missing.

---

## Order of operations (TDD wave)

1. **Routes** — add `resources :messages, only: [:create]` under conversations.
2. **Controller request specs** — POST happy path, POST forbidden, POST with empty content (validation).
3. **Controller** — minimum impl to pass.
4. **`MessageComponent`** — render one message with status icon placeholder (Plan 05d makes this real). Spec.
5. **Reply form partial + Turbo Frame integration** — view-level integration test.
6. **System spec** — agent fills form, clicks Send, sees message append.
7. **Regression sweep** — full app rspec + standardrb.

---

## What could go wrong

**Most likely:** Turbo Stream append targets the wrong DOM id and the message silently doesn't appear. Mitigation: the system spec asserts the message text appears in the thread after submit, end-to-end. If the spec fails on a real browser run, the issue is the target id — fix in Task 5.

**Least likely:** an unauthorized user gets a 200 because `current_user` is nil and the authz check returns `nil` (truthy-ish). Test the unauthenticated case explicitly (303 redirect to login from the existing auth filter, not 200).

---

## Task 1: Routes

**Files:**
- Modify: `packages/app/config/routes.rb`

- [ ] **Step 1: Failing routing spec**

`packages/app/spec/routing/dashboard_messages_routing_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "dashboard messages routing", type: :routing do
  it "POST /dashboard/conversations/1/messages routes to dashboard/messages#create" do
    expect(post: "/dashboard/conversations/1/messages")
      .to route_to(controller: "dashboard/messages", action: "create", conversation_id: "1")
  end
end
```

- [ ] **Step 2: Add nested resource**

```ruby
namespace :dashboard do
  resources :conversations, only: [:index, :show] do
    resources :messages, only: [:create]
  end
end
```

(Adjust `:index, :show` to match what's already there — the goal is to add `messages` nested under it, not redeclare the parent.)

- [ ] **Step 3: Verify spec passes, commit**

```bash
bundle exec rspec spec/routing/dashboard_messages_routing_spec.rb
git add packages/app/config/routes.rb packages/app/spec/routing
git commit -m "feat(routes): nest messages under dashboard/conversations"
```

---

## Task 2: Authorization predicate on `User`

**Files:**
- Modify: `packages/app/app/models/user.rb`
- Modify: `packages/app/spec/models/user_spec.rb`

- [ ] **Step 1: Spec**

```ruby
describe "#can_reply_to?" do
  let(:user) { create(:user) }
  let(:conversation) { create(:conversation, assignee: user) }

  it "is true when user is assignee" do
    expect(user.can_reply_to?(conversation)).to be true
  end

  it "is true for admins" do
    admin = create(:user, role: "admin")
    expect(admin.can_reply_to?(conversation)).to be true
  end

  it "is false otherwise" do
    other = create(:user)
    expect(other.can_reply_to?(conversation)).to be false
  end
end
```

(If `Conversation#assignee` doesn't exist yet, add `belongs_to :assignee, class_name: "User", optional: true` and a `assignee_id` column via migration. If `User#role` enum is missing, add it. Confirm by inspecting `app/models/user.rb` + `db/schema.rb` first; only add the missing pieces.)

- [ ] **Step 2: Run, verify fail, implement, verify pass**

```ruby
class User < ApplicationRecord
  def can_reply_to?(conversation)
    return true if respond_to?(:role) && role == "admin"
    conversation.assignee_id == id
  end
end
```

- [ ] **Step 3: Commit**

```bash
git add packages/app/app/models/user.rb packages/app/spec/models/user_spec.rb
git commit -m "feat(user): add can_reply_to? authorization predicate"
```

---

## Task 3: Controller request specs

**Files:**
- Create: `packages/app/spec/requests/dashboard/messages_spec.rb`

- [ ] **Step 1: Specs**

```ruby
require "rails_helper"

RSpec.describe "Dashboard::Messages", type: :request do
  let(:agent) { create(:user) }
  let(:channel) { create(:channel) }
  let(:conversation) { create(:conversation, channel: channel, assignee: agent) }

  before { sign_in agent }

  it "creates an outbound message and enqueues SendMessageJob" do
    expect {
      post dashboard_conversation_messages_path(conversation),
        params: {message: {content: "hi"}},
        headers: {"Accept" => "text/vnd.turbo-stream.html"}
    }.to change(Message, :count).by(1)
      .and have_enqueued_job(SendMessageJob)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include("hi")
  end

  it "rejects empty content with a 422" do
    post dashboard_conversation_messages_path(conversation),
      params: {message: {content: ""}},
      headers: {"Accept" => "text/vnd.turbo-stream.html"}
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "returns 403 when user cannot reply" do
    other_conversation = create(:conversation, channel: channel)
    post dashboard_conversation_messages_path(other_conversation),
      params: {message: {content: "hi"}}
    expect(response).to have_http_status(:forbidden)
  end

  it "redirects to login when unauthenticated" do
    sign_out
    post dashboard_conversation_messages_path(conversation),
      params: {message: {content: "hi"}}
    expect(response).to redirect_to(new_session_path)
  end
end
```

(`sign_in` / `sign_out` helpers are project-defined. If they don't exist, add minimal versions in `spec/support/auth_helpers.rb` that hit the existing Rails 8 `Session` model — do not introduce Devise.)

- [ ] **Step 2: Run, verify fail (controller missing)**

Expected: NameError or routing error.

- [ ] **Step 3: Stop here** — implementation in next task.

---

## Task 4: Controller implementation

**Files:**
- Create: `packages/app/app/controllers/dashboard/messages_controller.rb`

- [ ] **Step 1: Implement**

```ruby
class Dashboard::MessagesController < Dashboard::BaseController
  before_action :require_login
  before_action :load_conversation
  before_action :authorize_reply

  def create
    content = params.require(:message).permit(:content)[:content].to_s.strip

    if content.empty?
      render turbo_stream: turbo_stream.replace(
        "reply-form-#{@conversation.id}",
        partial: "dashboard/conversations/reply_form",
        locals: {conversation: @conversation, error: "Message cannot be blank"}
      ), status: :unprocessable_entity
      return
    end

    Dispatch::Outbound.call(
      conversation: @conversation,
      content: content,
      actor: Current.user
    )

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to dashboard_conversation_path(@conversation) }
    end
  end

  private

  def load_conversation
    @conversation = Conversation.find(params[:conversation_id])
  end

  def authorize_reply
    head :forbidden unless Current.user&.can_reply_to?(@conversation)
  end
end
```

(`Dashboard::BaseController` should already exist from earlier dashboard work. If not, create it as a thin `ApplicationController` subclass with `layout "dashboard"`. `require_login` and `Current.user` come from the Rails 8 auth scaffold installed in Spec 01.)

- [ ] **Step 2: View `create.turbo_stream.erb`**

```erb
<%= turbo_stream.append "messages-#{@conversation.id}" do %>
  <%= render(MessageComponent.new(message: Message.where(conversation: @conversation).order(:id).last)) %>
<% end %>

<%= turbo_stream.replace "reply-form-#{@conversation.id}",
      partial: "dashboard/conversations/reply_form",
      locals: {conversation: @conversation} %>
```

- [ ] **Step 3: Run request specs, verify all four pass**

```bash
bundle exec rspec spec/requests/dashboard/messages_spec.rb
```

- [ ] **Step 4: Commit**

```bash
git add packages/app/app/controllers/dashboard/messages_controller.rb \
        packages/app/app/views/dashboard/messages \
        packages/app/spec/requests/dashboard/messages_spec.rb
git commit -m "feat(dashboard): add reply controller calling Dispatch::Outbound"
```

---

## Task 5: `MessageComponent` + reply form partial

**Files:**
- Create: `packages/app/app/components/message_component.rb`
- Create: `packages/app/app/components/message_component.html.erb`
- Create: `packages/app/app/views/dashboard/conversations/_reply_form.html.erb`
- Modify: `packages/app/app/views/dashboard/conversations/show.html.erb`

- [ ] **Step 1: `MessageComponent`**

```ruby
class MessageComponent < ViewComponent::Base
  def initialize(message:)
    @message = message
  end

  def status_indicator
    return nil unless @message.outbound?
    # Plan 05d turns this into checkmark icons. For 05c just expose the status.
    tag.span(@message.status, class: "text-xs text-gray-400 status-indicator", data: {message_id: @message.id})
  end
end
```

```erb
<article id="message-<%= @message.id %>" class="<%= @message.outbound? ? 'self-end bg-blue-50' : 'bg-white' %> rounded-lg p-3 my-2 max-w-prose">
  <p><%= @message.content %></p>
  <%= status_indicator %>
</article>
```

- [ ] **Step 2: Reply form partial**

```erb
<%= turbo_frame_tag "reply-form-#{conversation.id}" do %>
  <%= form_with url: dashboard_conversation_messages_path(conversation), method: :post, data: {turbo_frame: "_top"} do |f| %>
    <% if local_assigns[:error] %>
      <p class="text-red-600 text-sm"><%= error %></p>
    <% end %>
    <%= f.fields_for :message do |m| %>
      <%= m.text_area :content, rows: 3, placeholder: "Type a reply…", class: "w-full border rounded p-2", required: true %>
    <% end %>
    <%= f.submit "Send", class: "bg-blue-600 text-white px-4 py-2 rounded" %>
  <% end %>
<% end %>
```

- [ ] **Step 3: Wire into `show.html.erb`**

```erb
<div id="messages-<%= @conversation.id %>" class="flex flex-col">
  <%= render(MessageComponent.with_collection(@conversation.messages.order(:id))) %>
</div>

<%= render "reply_form", conversation: @conversation %>
```

- [ ] **Step 4: Component spec**

`packages/app/spec/components/message_component_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe MessageComponent, type: :component do
  it "renders inbound message with default styling" do
    msg = build_stubbed(:message, direction: "inbound", content: "hi")
    render_inline(described_class.new(message: msg))
    expect(page).to have_css("article#message-#{msg.id}")
    expect(page).to have_text("hi")
    expect(page).not_to have_css(".status-indicator")
  end

  it "renders outbound with status indicator" do
    msg = build_stubbed(:message, direction: "outbound", status: "pending")
    render_inline(described_class.new(message: msg))
    expect(page).to have_css(".status-indicator", text: "pending")
  end
end
```

- [ ] **Step 5: Run all specs, verify pass**

```bash
bundle exec rspec spec/components/message_component_spec.rb spec/requests/dashboard/messages_spec.rb
```

- [ ] **Step 6: Commit**

```bash
git add packages/app/app/components packages/app/app/views/dashboard/conversations \
        packages/app/spec/components
git commit -m "feat(dashboard): MessageComponent + reply form partial with Turbo Frame"
```

---

## Task 6: System spec — full reply flow

**Files:**
- Create: `packages/app/spec/system/dashboard/reply_flow_spec.rb`

- [ ] **Step 1: Spec**

```ruby
require "rails_helper"

RSpec.describe "Reply flow", type: :system do
  let(:agent) { create(:user) }
  let(:conversation) { create(:conversation, assignee: agent) }

  before do
    driven_by(:cuprite)
    login_as(agent)
  end

  it "agent sends a reply and sees it appended to the thread" do
    stub_dispatch_client  # so SendMessageJob doesn't actually try to hit a container

    visit dashboard_conversation_path(conversation)
    fill_in "message[content]", with: "Hello there"
    click_button "Send"

    expect(page).to have_text("Hello there")
    expect(page).to have_css(".status-indicator", text: "pending")
  end
end
```

- [ ] **Step 2: Run, fix any selector/driver issues**

```bash
bundle exec rspec spec/system/dashboard/reply_flow_spec.rb
```

- [ ] **Step 3: Commit**

```bash
git add packages/app/spec/system
git commit -m "test(system): reply flow appends message via Turbo Stream"
```

---

## Task 7: Regression sweep + PROGRESS.md

- [ ] **Step 1: Full app rspec**

```bash
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && bundle exec rspec"
```

- [ ] **Step 2: standardrb**

```bash
docker exec falecom-workspace-1 bash -c "cd /workspaces/falecom/packages/app && bin/standardrb --fix"
```

- [ ] **Step 3: Update PROGRESS.md** — add 05c row.

- [ ] **Step 4: PR**

```bash
git push -u origin plan-05c-reply-form-dashboard
gh pr create --title "Plan 05c: Dashboard reply form + controller"
```
