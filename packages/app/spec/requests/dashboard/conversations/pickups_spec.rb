require "rails_helper"

RSpec.describe "Dashboard::Conversations::Pickups", type: :request do
  def make_user(role: "agent")
    User.create!(name: "U-#{SecureRandom.hex(3)}", email_address: "u-#{SecureRandom.hex(4)}@x.test",
      password: "password", role: role, availability: "online")
  end

  let(:team) { Team.create!(name: "T-#{SecureRandom.hex(3)}") }
  let(:channel) do
    Channel.create!(channel_type: "whatsapp_cloud", identifier: "id-#{SecureRandom.hex(4)}", name: "WA")
      .tap { |c| ChannelTeam.create!(channel: c, team: team) }
  end
  let(:agent) { make_user.tap { |u| TeamMember.create!(user: u, team: team) } }
  let(:conv) do
    contact = Contact.create!(name: "C")
    cc = ContactChannel.create!(channel: channel, contact: contact, source_id: "src-#{SecureRandom.hex(4)}")
    Conversation.create!(channel: channel, contact: contact, contact_channel: cc,
      display_id: SecureRandom.random_number(1_000_000) + 1,
      status: "queued", assignee: nil, team: team)
  end

  def sign_in(user)
    post session_path, params: {email_address: user.email_address, password: "password"}
  end

  it "assigns the conversation to current_user" do
    sign_in(agent)
    post dashboard_conversation_pickup_path(conv)
    expect(conv.reload).to have_attributes(assignee: agent, status: "assigned")
  end

  it "403 on inaccessible channel" do
    sign_in(agent)
    foreign_channel = Channel.create!(channel_type: "whatsapp_cloud", identifier: "x-#{SecureRandom.hex(3)}", name: "X")
    foreign_team = Team.create!(name: "F-#{SecureRandom.hex(3)}")
    ChannelTeam.create!(channel: foreign_channel, team: foreign_team)
    contact = Contact.create!(name: "C2")
    cc = ContactChannel.create!(channel: foreign_channel, contact: contact, source_id: "src-#{SecureRandom.hex(4)}")
    foreign = Conversation.create!(channel: foreign_channel, contact: contact, contact_channel: cc,
      display_id: SecureRandom.random_number(1_000_000) + 1, status: "queued", team: foreign_team)
    post dashboard_conversation_pickup_path(foreign)
    expect(response).to have_http_status(:forbidden)
  end
end
