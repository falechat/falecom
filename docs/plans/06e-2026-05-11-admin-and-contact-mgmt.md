# Plan 06e: Admin UI + Manual Contact Management

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans`.
> **Spec:** [06 — Assignment, Transfer & Workspace](../specs/06-assignment-transfer-workspace.md)
> **Date:** 2026-05-11
> **Status:** Draft — awaiting approval
> **Branch:** `plan-06e-admin-and-contact-mgmt`
> **Depends on:** Plan 06a (uses role checks via `ConversationPolicy`/`User#admin?`).

**Goal:** Ship admin CRUDs for Channels, Teams, Users (Spec §2.12) and manual contact creation with editable attributes + notes (Spec §2.13). After this plan, admins can configure channels/teams/users from the dashboard (instead of editing seeds.rb or the rails console), and agents can create contacts to start outbound conversations.

**Architecture:** Admin screens live under `/admin/*` and require `Current.user.admin?` — a tiny `RequireAdmin` controller concern returns 403 otherwise. All CRUDs are vanilla Rails resources with ViewComponent-driven tables; no fancy table libraries. Channel credentials remain encrypted at the model layer (Spec 02 already wired `encrypts :credentials`); the form accepts JSON-shaped credentials per channel type. Manual contact creation reuses `Contacts::Resolve` for idempotency: if the source_id already exists, it links instead of duplicating. Conversation notes use the same `Messages::Create` system-message convention introduced in 06b (`sender: nil`, `direction: "outbound"`, `status: "received"`) — they show in the timeline (06d) and never dispatch.

**Tech Stack:** Ruby 4.0.2, Rails 8.1.3, ViewComponent, Tailwind. No new gems.

---

## Files to touch

### Create — controllers / routes / concern

- `packages/app/app/controllers/concerns/require_admin.rb`
- `packages/app/app/controllers/admin/base_controller.rb`
- `packages/app/app/controllers/admin/channels_controller.rb`
- `packages/app/app/controllers/admin/teams_controller.rb`
- `packages/app/app/controllers/admin/users_controller.rb`
- `packages/app/app/controllers/dashboard/contacts_controller.rb`
- `packages/app/app/controllers/dashboard/conversations/notes_controller.rb`

### Create — views

- `packages/app/app/views/admin/channels/{index,new,edit,_form}.html.erb`
- `packages/app/app/views/admin/teams/{index,new,edit,_form}.html.erb`
- `packages/app/app/views/admin/users/{index,new,edit,_form}.html.erb`
- `packages/app/app/views/dashboard/contacts/{index,new,show}.html.erb`

### Create — components

- `packages/app/app/components/admin_table_component.rb` + `.html.erb` — generic table with headers + rows + actions
- `packages/app/app/components/availability_badge_component.rb` + `.html.erb`

### Create — services / forms

- `packages/app/app/services/contacts/create.rb`
- `packages/app/app/services/contacts/update_attributes.rb`

### Modify

- `packages/app/config/routes.rb` — add `namespace :admin` and `dashboard/contacts` + nested `notes`.

### Tests

- `packages/app/spec/requests/admin/channels_spec.rb`
- `packages/app/spec/requests/admin/teams_spec.rb`
- `packages/app/spec/requests/admin/users_spec.rb`
- `packages/app/spec/requests/dashboard/contacts_spec.rb`
- `packages/app/spec/requests/dashboard/conversations/notes_spec.rb`
- `packages/app/spec/services/contacts/create_spec.rb`
- `packages/app/spec/services/contacts/update_attributes_spec.rb`

---

## Order of operations

1. **`RequireAdmin` concern + `Admin::BaseController`** — gatekeeper, lays the namespace.
2. **Routes.**
3. **Channels CRUD** — most complex (encrypted credentials, auto-assign config).
4. **Teams CRUD** — simpler; manages members + channel attendance.
5. **Users CRUD** — invite/create, role, team membership, password reset link.
6. **Contacts manual creation + attributes** — `Contacts::Create` + `Contacts::UpdateAttributes`, controller, views.
7. **Conversation notes endpoint** — sibling of pickup/resolution under conversations.
8. **Regression + PROGRESS.**

---

## What could go wrong

**Most likely:** an admin saves a channel with malformed JSON credentials and the encrypted column silently stores the wrong shape. Mitigation: per-channel-type credential schemas validated in the controller via a small lookup table; reject with 422 on schema mismatch.

**Least likely:** routing collision between `dashboard/contacts/:id` and `dashboard/conversations/:id`. Each lives under its own resource — no collision.

---

## Task 1: `RequireAdmin` + `Admin::BaseController`

**Files:**
- Create: `packages/app/app/controllers/concerns/require_admin.rb`
- Create: `packages/app/app/controllers/admin/base_controller.rb`

- [ ] **Step 1: Implement**

```ruby
# app/controllers/concerns/require_admin.rb
module RequireAdmin
  extend ActiveSupport::Concern
  included do
    before_action :require_admin!
  end

  private

  def require_admin!
    head :forbidden unless Current.user&.admin?
  end
end
```

```ruby
# app/controllers/admin/base_controller.rb
module Admin
  class BaseController < ApplicationController
    include RequireAdmin
    layout "application"
  end
end
```

- [ ] **Step 2: Commit**

```bash
git add packages/app/app/controllers/concerns/require_admin.rb \
        packages/app/app/controllers/admin/base_controller.rb
git commit -m "chore(admin): RequireAdmin concern + Admin::BaseController"
```

---

## Task 2: Routes

**Files:**
- Modify: `packages/app/config/routes.rb`

- [ ] **Step 1: Add**

```ruby
namespace :admin do
  resources :channels
  resources :teams
  resources :users
  root to: "channels#index"
end

namespace :dashboard do
  # existing routes …
  resources :contacts
  resources :conversations, only: [:index, :show] do
    # existing nested routes …
    resource :note, only: [:create], module: :conversations
  end
end
```

- [ ] **Step 2: Verify with `bin/rails routes | grep -E 'admin|notes|contacts'`**.

- [ ] **Step 3: Commit**

```bash
git add packages/app/config/routes.rb
git commit -m "chore(routes): admin + contacts + notes routes"
```

---

## Task 3: Channels CRUD

**Files:**
- Create: `packages/app/app/controllers/admin/channels_controller.rb`
- Create: `packages/app/app/views/admin/channels/{index,new,edit,_form}.html.erb`
- Test: `packages/app/spec/requests/admin/channels_spec.rb`

- [ ] **Step 1: Failing request spec**

```ruby
require "rails_helper"

RSpec.describe "Admin::Channels", type: :request do
  let(:admin) { create(:user, role: "admin") }
  let(:agent) { create(:user, role: "agent") }

  describe "as admin" do
    before { sign_in_as(admin) }

    it "GET index lists channels" do
      channel = create(:channel, name: "WhatsApp BR")
      get admin_channels_path
      expect(response.body).to include("WhatsApp BR")
    end

    it "POST creates a channel with encrypted credentials" do
      post admin_channels_path, params: {channel: {
        name: "Test", channel_type: "whatsapp_cloud", identifier: "wa-test",
        credentials: {access_token: "tok", phone_number_id: "pn"}.to_json,
        auto_assign: "1", auto_assign_config: {strategy: "round_robin"}.to_json
      }}
      expect(response).to redirect_to(admin_channels_path)
      ch = Channel.find_by(identifier: "wa-test")
      expect(ch.credentials.deep_symbolize_keys).to include(access_token: "tok")
      expect(ch.auto_assign).to be true
    end

    it "PATCH updates" do
      ch = create(:channel)
      patch admin_channel_path(ch), params: {channel: {name: "Renamed"}}
      expect(ch.reload.name).to eq("Renamed")
    end

    it "DELETE soft-flips active to false (cannot truly destroy due to has_many :restrict)" do
      ch = create(:channel)
      delete admin_channel_path(ch)
      expect(ch.reload.active).to be false
    end

    it "422s on malformed credentials JSON" do
      post admin_channels_path, params: {channel: {name: "x", channel_type: "whatsapp_cloud", identifier: "x", credentials: "{nope"}}
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "as non-admin" do
    before { sign_in_as(agent) }
    it "403s on index" do
      get admin_channels_path
      expect(response).to have_http_status(:forbidden)
    end
  end
end
```

- [ ] **Step 2: Implement controller**

```ruby
module Admin
  class ChannelsController < BaseController
    before_action :load, only: [:edit, :update, :destroy]

    def index
      @channels = Channel.order(:name)
    end

    def new
      @channel = Channel.new
    end

    def create
      @channel = Channel.new(parsed_params)
      if @channel.save
        redirect_to admin_channels_path, notice: "Channel created"
      else
        render :new, status: :unprocessable_content
      end
    rescue JSON::ParserError => e
      @channel ||= Channel.new
      @channel.errors.add(:credentials, e.message)
      render :new, status: :unprocessable_content
    end

    def edit
    end

    def update
      if @channel.update(parsed_params)
        redirect_to admin_channels_path, notice: "Updated"
      else
        render :edit, status: :unprocessable_content
      end
    rescue JSON::ParserError => e
      @channel.errors.add(:credentials, e.message)
      render :edit, status: :unprocessable_content
    end

    def destroy
      @channel.update!(active: false)
      redirect_to admin_channels_path, notice: "Deactivated"
    end

    private

    def load = @channel = Channel.find(params[:id])

    def parsed_params
      raw = params.require(:channel).permit(:name, :channel_type, :identifier, :active, :auto_assign, :credentials, :auto_assign_config)
      raw[:credentials] = JSON.parse(raw[:credentials]) if raw[:credentials].is_a?(String) && raw[:credentials].present?
      raw[:auto_assign_config] = JSON.parse(raw[:auto_assign_config]) if raw[:auto_assign_config].is_a?(String) && raw[:auto_assign_config].present?
      raw
    end
  end
end
```

- [ ] **Step 3: Views**

`index.html.erb`:

```erb
<h1 class="text-xl font-semibold mb-4">Channels</h1>
<%= link_to "New channel", new_admin_channel_path, class: "btn-primary mb-3 inline-block" %>
<table class="w-full text-sm">
  <thead><tr class="text-left border-b"><th>Name</th><th>Type</th><th>Identifier</th><th>Active</th><th>Auto-Assign</th><th></th></tr></thead>
  <tbody>
    <% @channels.each do |c| %>
      <tr class="border-b">
        <td><%= c.name %></td>
        <td><%= c.channel_type %></td>
        <td><code><%= c.identifier %></code></td>
        <td><%= c.active? ? "✓" : "—" %></td>
        <td><%= c.auto_assign? ? c.auto_assign_config["strategy"] : "—" %></td>
        <td class="text-right">
          <%= link_to "Edit", edit_admin_channel_path(c) %> ·
          <%= button_to "Deactivate", admin_channel_path(c), method: :delete, class: "text-red-600", data: {turbo_confirm: "Sure?"} %>
        </td>
      </tr>
    <% end %>
  </tbody>
</table>
```

`new.html.erb` / `edit.html.erb` each render `_form.html.erb`:

```erb
<%= form_with model: @channel, url: @channel.persisted? ? admin_channel_path(@channel) : admin_channels_path do |f| %>
  <% if @channel.errors.any? %>
    <ul class="text-red-600 mb-3"><% @channel.errors.full_messages.each do |m| %><li><%= m %></li><% end %></ul>
  <% end %>
  <div class="grid grid-cols-2 gap-3">
    <%= f.label :name %>          <%= f.text_field :name, class: "input" %>
    <%= f.label :channel_type %>  <%= f.select :channel_type, %w[whatsapp_cloud zapi evolution instagram telegram] %>
    <%= f.label :identifier %>    <%= f.text_field :identifier, class: "input" %>
    <%= f.label :active %>        <%= f.check_box :active %>
    <%= f.label :auto_assign %>   <%= f.check_box :auto_assign %>
  </div>
  <%= f.label :credentials, "Credentials (JSON)" %>
  <%= f.text_area :credentials, value: @channel.credentials.to_json, rows: 5, class: "input w-full font-mono" %>
  <%= f.label :auto_assign_config, "Auto-Assign Config (JSON)" %>
  <%= f.text_area :auto_assign_config, value: @channel.auto_assign_config.to_json, rows: 3, class: "input w-full font-mono" %>
  <%= f.submit class: "btn-primary mt-3" %>
<% end %>
```

- [ ] **Step 4: Pass + commit**

```bash
git add packages/app/app/controllers/admin/channels_controller.rb \
        packages/app/app/views/admin/channels/ \
        packages/app/spec/requests/admin/channels_spec.rb
git commit -m "feat(admin): Channels CRUD"
```

---

## Task 4: Teams CRUD

**Files:**
- Create: `packages/app/app/controllers/admin/teams_controller.rb`
- Create: `packages/app/app/views/admin/teams/{index,new,edit,_form}.html.erb`
- Test: `packages/app/spec/requests/admin/teams_spec.rb`

- [ ] **Step 1: Failing spec**

```ruby
require "rails_helper"
RSpec.describe "Admin::Teams", type: :request do
  let(:admin) { create(:user, role: "admin") }
  before { sign_in_as(admin) }

  it "creates a team with channel + member assignments" do
    ch = create(:channel)
    u = create(:user)
    post admin_teams_path, params: {team: {name: "Sales", user_ids: [u.id], channel_ids: [ch.id]}}
    team = Team.find_by(name: "Sales")
    expect(team.users).to include(u)
    expect(team.channels).to include(ch)
  end

  it "updates membership idempotently" do
    team = create(:team)
    u1 = create(:user); u2 = create(:user)
    TeamMember.create!(user: u1, team: team)
    patch admin_team_path(team), params: {team: {user_ids: [u2.id]}}
    expect(team.reload.users).to contain_exactly(u2)
  end
end
```

- [ ] **Step 2: Implement**

```ruby
module Admin
  class TeamsController < BaseController
    before_action :load, only: [:edit, :update, :destroy]

    def index = (@teams = Team.includes(:users, :channels).order(:name))
    def new = (@team = Team.new)

    def create
      @team = Team.new(name: team_params[:name])
      if @team.save
        sync(team_params[:user_ids], team_params[:channel_ids])
        redirect_to admin_teams_path, notice: "Created"
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
    end

    def update
      if @team.update(name: team_params[:name])
        sync(team_params[:user_ids], team_params[:channel_ids])
        redirect_to admin_teams_path
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @team.destroy
      redirect_to admin_teams_path
    end

    private

    def load = @team = Team.find(params[:id])
    def team_params = params.require(:team).permit(:name, user_ids: [], channel_ids: [])

    def sync(user_ids, channel_ids)
      if user_ids
        TeamMember.where(team: @team).delete_all
        Array(user_ids).reject(&:blank?).each { |uid| TeamMember.create!(team: @team, user_id: uid) }
      end
      if channel_ids
        ChannelTeam.where(team: @team).delete_all
        Array(channel_ids).reject(&:blank?).each { |cid| ChannelTeam.create!(team: @team, channel_id: cid) }
      end
    end
  end
end
```

- [ ] **Step 3: Views**

`index.html.erb`:

```erb
<h1 class="text-xl font-semibold mb-4">Teams</h1>
<%= link_to "New team", new_admin_team_path, class: "btn-primary inline-block mb-3" %>
<table class="w-full text-sm">
  <thead><tr class="border-b text-left"><th>Name</th><th>Members</th><th>Channels</th><th></th></tr></thead>
  <tbody>
    <% @teams.each do |t| %>
      <tr class="border-b">
        <td><%= t.name %></td>
        <td><%= t.users.map(&:name).join(", ") %></td>
        <td><%= t.channels.map(&:name).join(", ") %></td>
        <td class="text-right"><%= link_to "Edit", edit_admin_team_path(t) %></td>
      </tr>
    <% end %>
  </tbody>
</table>
```

`_form.html.erb`:

```erb
<%= form_with model: @team, url: @team.persisted? ? admin_team_path(@team) : admin_teams_path do |f| %>
  <%= f.label :name %><%= f.text_field :name, class: "input w-full" %>
  <%= f.label :user_ids, "Members" %>
  <%= f.collection_check_boxes :user_ids, User.order(:name), :id, :name %>
  <%= f.label :channel_ids, "Channels attended" %>
  <%= f.collection_check_boxes :channel_ids, Channel.where(active: true).order(:name), :id, :name %>
  <%= f.submit class: "btn-primary mt-3" %>
<% end %>
```

- [ ] **Step 4: Pass + commit**

```bash
git add packages/app/app/controllers/admin/teams_controller.rb \
        packages/app/app/views/admin/teams/ \
        packages/app/spec/requests/admin/teams_spec.rb
git commit -m "feat(admin): Teams CRUD with membership + channel attendance"
```

---

## Task 5: Users CRUD

**Files:**
- Create: `packages/app/app/controllers/admin/users_controller.rb`
- Create: `packages/app/app/views/admin/users/{index,new,edit,_form}.html.erb`
- Create: `packages/app/app/components/availability_badge_component.{rb,html.erb}`
- Test: `packages/app/spec/requests/admin/users_spec.rb`

- [ ] **Step 1: Failing spec**

```ruby
require "rails_helper"
RSpec.describe "Admin::Users", type: :request do
  let(:admin) { create(:user, role: "admin") }
  before { sign_in_as(admin) }

  it "creates a user with role + team membership" do
    team = create(:team)
    post admin_users_path, params: {user: {name: "Maria", email_address: "m@x.com", password: "abcdef12", role: "agent", team_ids: [team.id]}}
    u = User.find_by(email_address: "m@x.com")
    expect(u.role).to eq("agent")
    expect(u.teams).to include(team)
  end

  it "PATCH updates without requiring password" do
    u = create(:user)
    patch admin_user_path(u), params: {user: {name: "New name"}}
    expect(u.reload.name).to eq("New name")
  end
end
```

- [ ] **Step 2: Implement**

```ruby
module Admin
  class UsersController < BaseController
    before_action :load, only: [:edit, :update, :destroy]

    def index = (@users = User.includes(:teams).order(:name))
    def new = (@user = User.new)

    def create
      @user = User.new(user_params)
      if @user.save
        sync_teams(team_ids)
        redirect_to admin_users_path
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
    end

    def update
      attrs = user_params
      attrs.delete(:password) if attrs[:password].blank?
      if @user.update(attrs)
        sync_teams(team_ids)
        redirect_to admin_users_path
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @user.destroy
      redirect_to admin_users_path
    end

    private

    def load = @user = User.find(params[:id])
    def user_params = params.require(:user).permit(:name, :email_address, :role, :password)
    def team_ids = params.require(:user).permit(team_ids: [])[:team_ids]

    def sync_teams(ids)
      return if ids.nil?
      TeamMember.where(user: @user).delete_all
      Array(ids).reject(&:blank?).each { |tid| TeamMember.create!(user: @user, team_id: tid) }
    end
  end
end
```

`AvailabilityBadgeComponent`:

```ruby
class AvailabilityBadgeComponent < ViewComponent::Base
  COLOR = {"online" => "bg-green-500", "busy" => "bg-yellow-500", "offline" => "bg-gray-400"}.freeze
  def initialize(user:) ; @user = user ; end
end
```

```erb
<span class="inline-flex items-center gap-1 text-xs">
  <span class="w-2 h-2 rounded-full <%= AvailabilityBadgeComponent::COLOR[@user.availability] %>"></span>
  <%= @user.availability.titleize %>
</span>
```

Views mirror channels/teams patterns.

- [ ] **Step 3: Pass + commit**

```bash
git add packages/app/app/controllers/admin/users_controller.rb \
        packages/app/app/views/admin/users/ \
        packages/app/app/components/availability_badge_component* \
        packages/app/spec/requests/admin/users_spec.rb
git commit -m "feat(admin): Users CRUD + availability badge"
```

---

## Task 6: Manual contact creation + attributes

**Files:**
- Create: `packages/app/app/services/contacts/create.rb`
- Create: `packages/app/app/services/contacts/update_attributes.rb`
- Create: `packages/app/app/controllers/dashboard/contacts_controller.rb`
- Create: `packages/app/app/views/dashboard/contacts/{index,new,show}.html.erb`
- Test: `packages/app/spec/services/contacts/create_spec.rb`
- Test: `packages/app/spec/services/contacts/update_attributes_spec.rb`
- Test: `packages/app/spec/requests/dashboard/contacts_spec.rb`

- [ ] **Step 1: Failing service specs**

```ruby
# spec/services/contacts/create_spec.rb
require "rails_helper"
RSpec.describe Contacts::Create do
  let(:channel) { create(:channel) }

  it "creates a contact with optional contact_channel" do
    contact = described_class.call(name: "Maria", phone_number: "+5511...", channel: channel, source_id: "5511...")
    expect(contact).to be_persisted
    expect(contact.contact_channels.where(channel: channel, source_id: "5511...")).to exist
  end

  it "reuses existing contact_channel" do
    existing = create(:contact)
    ContactChannel.create!(contact: existing, channel: channel, source_id: "5511...")
    contact = described_class.call(name: "Whatever", channel: channel, source_id: "5511...")
    expect(contact).to eq(existing)
  end
end
```

```ruby
# spec/services/contacts/update_attributes_spec.rb
require "rails_helper"
RSpec.describe Contacts::UpdateAttributes do
  let(:contact) { create(:contact, additional_attributes: {"plan" => "free"}) }

  it "merges attrs" do
    described_class.call(contact: contact, additional_attributes: {"plan" => "enterprise", "crm_url" => "https://x"})
    expect(contact.reload.additional_attributes).to eq("plan" => "enterprise", "crm_url" => "https://x")
  end

  it "removes keys passed as nil" do
    described_class.call(contact: contact, additional_attributes: {"plan" => nil})
    expect(contact.reload.additional_attributes).to eq({})
  end
end
```

- [ ] **Step 2: Implement**

```ruby
module Contacts
  class Create
    def self.call(name: nil, phone_number: nil, email: nil, channel: nil, source_id: nil)
      contact = if channel && source_id
        existing = ContactChannel.find_by(channel: channel, source_id: source_id)&.contact
        existing || Contact.create!(name: name, phone_number: phone_number, email: email)
      else
        Contact.create!(name: name, phone_number: phone_number, email: email)
      end
      contact.update!(name: name, phone_number: phone_number, email: email) if name || phone_number || email
      ContactChannel.find_or_create_by!(contact: contact, channel: channel, source_id: source_id) if channel && source_id
      contact
    end
  end

  class UpdateAttributes
    def self.call(contact:, additional_attributes:)
      next_attrs = contact.additional_attributes.merge(additional_attributes.stringify_keys)
      next_attrs.reject! { |_k, v| v.nil? }
      contact.update!(additional_attributes: next_attrs)
      contact
    end
  end
end
```

- [ ] **Step 3: Controller + views**

```ruby
module Dashboard
  class ContactsController < ApplicationController
    def index = (@contacts = Contact.order(:name).limit(100))
    def new = (@contact = Contact.new)

    def create
      @contact = Contacts::Create.call(
        name: params[:contact][:name],
        phone_number: params[:contact][:phone_number],
        email: params[:contact][:email]
      )
      redirect_to dashboard_contact_path(@contact)
    end

    def show
      @contact = Contact.find(params[:id])
    end

    def update
      @contact = Contact.find(params[:id])
      @contact.update!(params.require(:contact).permit(:name, :phone_number, :email))
      if params[:contact][:additional_attributes].is_a?(Hash)
        Contacts::UpdateAttributes.call(contact: @contact, additional_attributes: params[:contact][:additional_attributes])
      end
      redirect_to dashboard_contact_path(@contact)
    end
  end
end
```

`new.html.erb` is a vanilla form for name + phone + email. `show.html.erb` shows the same plus an editable key/value table backed by `additional_attributes`:

```erb
<h1><%= @contact.name %></h1>
<%= form_with model: @contact, url: dashboard_contact_path(@contact), method: :patch do |f| %>
  <%= f.text_field :name %>
  <%= f.text_field :phone_number %>
  <%= f.text_field :email %>

  <h3 class="mt-4">Attributes</h3>
  <div data-controller="kv-attrs">
    <% @contact.additional_attributes.each do |k, v| %>
      <div class="flex gap-2">
        <input name="contact[additional_attributes][<%= k %>]" value="<%= v %>" class="input">
        <button type="button" data-action="kv-attrs#remove" data-key="<%= k %>">Remove</button>
      </div>
    <% end %>
    <button type="button" data-action="kv-attrs#add">+ Add attribute</button>
  </div>

  <%= f.submit %>
<% end %>
```

A small Stimulus `kv-attrs` controller appends `<input name="contact[additional_attributes][<key>]">` pairs. Implementation is mechanical; keep it under 40 lines.

- [ ] **Step 4: Request spec**

```ruby
require "rails_helper"
RSpec.describe "Dashboard::Contacts", type: :request do
  let(:agent) { create(:user, role: "agent") }
  before { sign_in_as(agent) }

  it "creates a contact" do
    expect { post dashboard_contacts_path, params: {contact: {name: "Maria", phone_number: "+55..."}} }
      .to change(Contact, :count).by(1)
  end

  it "updates attributes" do
    c = create(:contact)
    patch dashboard_contact_path(c), params: {contact: {additional_attributes: {"plan" => "enterprise"}}}
    expect(c.reload.additional_attributes).to eq("plan" => "enterprise")
  end
end
```

- [ ] **Step 5: Pass + commit**

```bash
git add packages/app/app/services/contacts/ \
        packages/app/app/controllers/dashboard/contacts_controller.rb \
        packages/app/app/views/dashboard/contacts/ \
        packages/app/spec/services/contacts/ \
        packages/app/spec/requests/dashboard/contacts_spec.rb
git commit -m "feat(contacts): manual creation + ad-hoc attributes editor"
```

---

## Task 7: Conversation notes endpoint

**Files:**
- Create: `packages/app/app/controllers/dashboard/conversations/notes_controller.rb`
- Test: `packages/app/spec/requests/dashboard/conversations/notes_spec.rb`

- [ ] **Step 1: Failing spec**

```ruby
require "rails_helper"
RSpec.describe "Dashboard::Conversations::Notes", type: :request do
  let(:team) { create(:team) }
  let(:channel) { create(:channel).tap { |c| ChannelTeam.create!(channel: c, team: team) } }
  let(:agent) { create(:user, role: "agent").tap { |u| TeamMember.create!(user: u, team: team) } }
  let(:conv) { create(:conversation, channel: channel, team: team, assignee: agent, status: "assigned") }

  before { sign_in_as(agent) }

  it "creates a system message in the conversation" do
    expect {
      post dashboard_conversation_note_path(conv), params: {note: {content: "internal: VIP"}}
    }.to change { conv.messages.count }.by(1)
    msg = conv.messages.order(:created_at).last
    expect(msg).to have_attributes(sender: nil, direction: "outbound", status: "received", content: "internal: VIP")
  end

  it "does NOT enqueue SendMessageJob" do
    expect {
      post dashboard_conversation_note_path(conv), params: {note: {content: "x"}}
    }.not_to have_enqueued_job(SendMessageJob)
  end

  it "403s when not authorized to view" do
    foreign = create(:conversation)
    post dashboard_conversation_note_path(foreign), params: {note: {content: "x"}}
    expect(response).to have_http_status(:forbidden)
  end
end
```

- [ ] **Step 2: Implement**

```ruby
module Dashboard
  module Conversations
    class NotesController < ApplicationController
      def create
        conv = ::Conversation.find(params[:conversation_id])
        head :forbidden and return unless ConversationPolicy.new(Current.user, conv).can_view?
        ::Messages::Create.call(
          conversation: conv,
          direction: "outbound",
          content: params.dig(:note, :content),
          content_type: "text",
          status: "received",
          sender: nil
        )
        redirect_to dashboard_conversation_path(conv)
      end
    end
  end
end
```

- [ ] **Step 3: Pass + commit**

```bash
git add packages/app/app/controllers/dashboard/conversations/notes_controller.rb \
        packages/app/spec/requests/dashboard/conversations/notes_spec.rb
git commit -m "feat(conversations): internal notes endpoint (system message, no dispatch)"
```

---

## Task 8: Regression + PROGRESS

- [ ] **Step 1: Full suite + standardrb**

Run: `bundle exec rspec && bin/standardrb --fix`
Expected: green.

- [ ] **Step 2: Manual smoke**

Login as admin. Create a channel, team, user. Login as the new agent. Add team membership through admin. Verify the agent sees the channel's conversations after a refresh.

- [ ] **Step 3: Update `docs/PROGRESS.md`** — add 06e row.

- [ ] **Step 4: PR**

```bash
git push -u origin plan-06e-admin-and-contact-mgmt
gh pr create --title "Plan 06e: Admin UI + Contact management" \
             --body-file docs/plans/06e-2026-05-11-admin-and-contact-mgmt.md
```

---

You can now run `/clear` and `/execute-plan docs/plans/06f-2026-05-11-realtime-scoping.md`.
