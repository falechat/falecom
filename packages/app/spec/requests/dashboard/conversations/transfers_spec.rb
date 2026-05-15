require "rails_helper"

RSpec.describe "Dashboard::Conversations::Transfers", type: :request do
  def make_user(role: "agent")
    User.create!(name: "U-#{SecureRandom.hex(3)}", email_address: "u-#{SecureRandom.hex(4)}@x.test",
      password: "password", role: role, availability: "online")
  end

  let(:team_a) { Team.create!(name: "A-#{SecureRandom.hex(3)}") }
  let(:team_b) { Team.create!(name: "B-#{SecureRandom.hex(3)}") }
  let(:channel) do
    Channel.create!(channel_type: "whatsapp_cloud", identifier: "id-#{SecureRandom.hex(4)}", name: "WA").tap do |c|
      ChannelTeam.create!(channel: c, team: team_a)
      ChannelTeam.create!(channel: c, team: team_b)
    end
  end
  let(:agent) { make_user.tap { |u| TeamMember.create!(user: u, team: team_a) } }
  let(:agent_b) { make_user.tap { |u| TeamMember.create!(user: u, team: team_b) } }
  let(:conv) do
    contact = Contact.create!(name: "C")
    cc = ContactChannel.create!(channel: channel, contact: contact, source_id: "src-#{SecureRandom.hex(4)}")
    Conversation.create!(channel: channel, contact: contact, contact_channel: cc,
      display_id: SecureRandom.random_number(1_000_000) + 1,
      status: "assigned", assignee: agent, team: team_a)
  end

  def sign_in(user)
    post session_path, params: {email_address: user.email_address, password: "password"}
  end

  it "GET new renders the transfer modal" do
    sign_in(agent)
    get new_dashboard_conversation_transfer_path(conv)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Transfer")
  end

  it "POST create transfers and redirects" do
    sign_in(agent)
    post dashboard_conversation_transfer_path(conv),
      params: {transfer: {to_team_id: team_b.id, to_user_id: agent_b.id, note: "context"}}
    expect(response).to redirect_to(dashboard_conversation_path(conv))
    expect(conv.reload).to have_attributes(team: team_b, assignee: agent_b)
  end

  it "POST returns 403 when unauthorized" do
    sign_in(make_user)
    post dashboard_conversation_transfer_path(conv), params: {transfer: {to_user_id: agent_b.id}}
    expect(response).to have_http_status(:forbidden)
  end

  it "POST returns 422 on validation error" do
    sign_in(agent)
    orphan = Team.create!(name: "orphan-#{SecureRandom.hex(3)}")
    post dashboard_conversation_transfer_path(conv), params: {transfer: {to_team_id: orphan.id}}
    expect(response).to have_http_status(:unprocessable_content)
  end
end
