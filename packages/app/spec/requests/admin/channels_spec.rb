require "rails_helper"

RSpec.describe "Admin::Channels", type: :request do
  def make_user(role: "agent")
    User.create!(name: "U-#{SecureRandom.hex(3)}", email_address: "u-#{SecureRandom.hex(4)}@x.test",
      password: "password", role: role, availability: "online")
  end

  def make_channel(name: "WA", identifier: "wa-#{SecureRandom.hex(3)}")
    Channel.create!(channel_type: "whatsapp_cloud", identifier: identifier, name: name)
  end

  def sign_in(user)
    post session_path, params: {email_address: user.email_address, password: "password"}
  end

  let(:admin) { make_user(role: "admin") }
  let(:agent) { make_user(role: "agent") }

  describe "as admin" do
    before { sign_in(admin) }

    it "GET index lists channels" do
      make_channel(name: "WhatsApp BR")
      get admin_channels_path
      expect(response.body).to include("WhatsApp BR")
    end

    it "POST creates a channel with encrypted credentials" do
      post admin_channels_path, params: {channel: {
        name: "Test", channel_type: "whatsapp_cloud", identifier: "wa-test", active: "1",
        credentials: {access_token: "tok", phone_number_id: "pn"}.to_json,
        auto_assign: "1", auto_assign_config: {strategy: "round_robin"}.to_json
      }}
      expect(response).to redirect_to(admin_channels_path)
      ch = Channel.find_by(identifier: "wa-test")
      expect(ch.credentials.deep_symbolize_keys).to include(access_token: "tok")
      expect(ch.auto_assign).to be true
    end

    it "PATCH updates" do
      ch = make_channel
      patch admin_channel_path(ch), params: {channel: {name: "Renamed"}}
      expect(ch.reload.name).to eq("Renamed")
    end

    it "DELETE soft-deactivates" do
      ch = make_channel
      delete admin_channel_path(ch)
      expect(ch.reload.active).to be false
    end

    it "422s on malformed credentials JSON" do
      post admin_channels_path, params: {channel: {name: "x", channel_type: "whatsapp_cloud", identifier: "x-#{SecureRandom.hex(3)}", credentials: "{nope"}}
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "as non-admin" do
    before { sign_in(agent) }

    it "403s on index" do
      get admin_channels_path
      expect(response).to have_http_status(:forbidden)
    end
  end
end
