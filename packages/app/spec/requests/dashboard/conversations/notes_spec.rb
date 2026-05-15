require "rails_helper"

RSpec.describe "Dashboard::Conversations::Notes", type: :request do
  def make_user(role: "agent")
    User.create!(name: "U-#{SecureRandom.hex(3)}", email_address: "u-#{SecureRandom.hex(4)}@x.test",
      password: "password", role: role, availability: "online")
  end

  def sign_in(user)
    post session_path, params: {email_address: user.email_address, password: "password"}
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
      status: "assigned", assignee: agent, team: team)
  end

  before { sign_in(agent) }

  it "creates a system message in the conversation" do
    expect {
      post dashboard_conversation_note_path(conv), params: {note: {content: "internal: VIP"}}
    }.to change { conv.messages.count }.by(1)
    msg = conv.messages.order(:created_at).last
    expect(msg).to have_attributes(sender_id: nil, sender_type: nil, direction: "outbound", status: "received", content: "internal: VIP")
  end

  it "does NOT enqueue SendMessageJob" do
    expect {
      post dashboard_conversation_note_path(conv), params: {note: {content: "x"}}
    }.not_to have_enqueued_job(SendMessageJob)
  end

  it "403s when not authorized to view" do
    foreign_channel = Channel.create!(channel_type: "whatsapp_cloud", identifier: "f-#{SecureRandom.hex(3)}", name: "F")
    foreign_team = Team.create!(name: "F-#{SecureRandom.hex(3)}")
    ChannelTeam.create!(channel: foreign_channel, team: foreign_team)
    contact = Contact.create!(name: "C2")
    cc = ContactChannel.create!(channel: foreign_channel, contact: contact, source_id: "src-#{SecureRandom.hex(4)}")
    foreign = Conversation.create!(channel: foreign_channel, contact: contact, contact_channel: cc,
      display_id: SecureRandom.random_number(1_000_000) + 1, status: "queued", team: foreign_team)
    post dashboard_conversation_note_path(foreign), params: {note: {content: "x"}}
    expect(response).to have_http_status(:forbidden)
  end
end
