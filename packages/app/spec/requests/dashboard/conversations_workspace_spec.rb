require "rails_helper"

RSpec.describe "Dashboard workspace", type: :request do
  def make_user(role: "agent")
    User.create!(name: "U-#{SecureRandom.hex(3)}", email_address: "u-#{SecureRandom.hex(4)}@x.test",
      password: "password", role: role, availability: "online")
  end

  def make_channel(team: nil)
    ch = Channel.create!(channel_type: "whatsapp_cloud", identifier: "id-#{SecureRandom.hex(4)}", name: "C-#{SecureRandom.hex(2)}")
    ChannelTeam.create!(channel: ch, team: team) if team
    ch
  end

  def make_conv(channel:, status: "queued", assignee: nil, team: nil)
    contact = Contact.create!(name: "C-#{SecureRandom.hex(3)}")
    cc = ContactChannel.create!(channel: channel, contact: contact, source_id: "src-#{SecureRandom.hex(4)}")
    Conversation.create!(channel: channel, contact: contact, contact_channel: cc,
      display_id: SecureRandom.random_number(1_000_000) + 1,
      status: status, assignee: assignee, team: team)
  end

  def sign_in(user)
    post session_path, params: {email_address: user.email_address, password: "password"}
  end

  let(:team) { Team.create!(name: "T-#{SecureRandom.hex(3)}") }
  let(:channel_a) { make_channel(team: team) }
  let(:channel_b) { make_channel(team: Team.create!(name: "F-#{SecureRandom.hex(2)}")) }
  let(:agent) { make_user.tap { |u| TeamMember.create!(user: u, team: team) } }
  let!(:mine)    { make_conv(channel: channel_a, assignee: agent, status: "assigned") }
  let!(:queued)  { make_conv(channel: channel_a, status: "queued") }
  let!(:foreign) { make_conv(channel: channel_b, status: "queued") }

  before { sign_in(agent) }

  it "GET /dashboard/conversations?view=mine returns only mine" do
    get dashboard_conversations_path(view: "mine")
    expect(response.body).to include("##{mine.display_id}")
    expect(response.body).not_to include("##{queued.display_id}")
  end

  it "view=unassigned excludes foreign channels" do
    get dashboard_conversations_path(view: "unassigned")
    expect(response.body).to include("##{queued.display_id}")
    expect(response.body).not_to include("##{foreign.display_id}")
  end

  it "show renders inside the workspace layout" do
    get dashboard_conversation_path(mine)
    expect(response.body).to include("active-conversation")
  end

  it "403s when an agent tries to view a foreign conversation directly" do
    get dashboard_conversation_path(foreign)
    expect(response).to have_http_status(:forbidden)
  end
end
