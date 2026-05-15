require "rails_helper"

RSpec.describe Conversations::Resolve do
  def make_user(role: "agent")
    User.create!(name: "U-#{SecureRandom.hex(3)}", email_address: "u-#{SecureRandom.hex(4)}@x.test",
      password: "password", role: role, availability: "online")
  end

  let(:team) { Team.create!(name: "T-#{SecureRandom.hex(3)}") }
  let(:channel) do
    Channel.create!(channel_type: "whatsapp_cloud", identifier: "id-#{SecureRandom.hex(4)}", name: "WA")
      .tap { |c| ChannelTeam.create!(channel: c, team: team) }
  end
  let(:user) { make_user.tap { |u| TeamMember.create!(user: u, team: team) } }
  let(:conv) do
    contact = Contact.create!(name: "C")
    cc = ContactChannel.create!(channel: channel, contact: contact, source_id: "src-#{SecureRandom.hex(4)}")
    Conversation.create!(channel: channel, contact: contact, contact_channel: cc,
      display_id: SecureRandom.random_number(1_000_000) + 1,
      status: "assigned", assignee: user, team: team)
  end

  it "resolves and emits event" do
    expect {
      described_class.call(conversation: conv, actor: user)
    }.to change { conv.reload.status }.from("assigned").to("resolved")
      .and change { Event.where(name: "conversations:resolved", subject: conv).count }.by(1)
  end

  it "raises AuthorizationError otherwise" do
    stranger = make_user
    expect {
      described_class.call(conversation: conv, actor: stranger)
    }.to raise_error(FaleCom::AuthorizationError)
  end
end
