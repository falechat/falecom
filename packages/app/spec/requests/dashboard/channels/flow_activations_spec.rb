require "rails_helper"

RSpec.describe "Dashboard::Channels::FlowActivations", type: :request do
  def make_user(role: "admin")
    User.create!(name: "U-#{SecureRandom.hex(3)}", email_address: "u-#{SecureRandom.hex(4)}@x.test",
      password: "password", role: role, availability: "online")
  end

  def sign_in(user)
    post session_path, params: {email_address: user.email_address, password: "password"}
  end

  let(:admin) { make_user(role: "admin") }
  let(:channel) { Channel.create!(name: "c", channel_type: "whatsapp_cloud", identifier: "c-#{SecureRandom.hex(3)}") }
  let(:flow) { Flow.create!(name: "f") }

  before { sign_in(admin) }

  it "POST activates a flow on a channel" do
    post dashboard_channel_flow_activation_path(channel), params: {flow_id: flow.id}
    expect(channel.reload.active_flow).to eq(flow)
  end

  it "DELETE deactivates" do
    channel.update!(active_flow: flow)
    delete dashboard_channel_flow_activation_path(channel)
    expect(channel.reload.active_flow).to be_nil
  end
end
