require "rails_helper"

RSpec.describe ConversationStreamGate do
  def make_user
    User.create!(
      name: "U-#{SecureRandom.hex(3)}",
      email_address: "u-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      role: "agent"
    )
  end

  let(:team) { Team.create!(name: "T-#{SecureRandom.hex(3)}") }
  let(:channel) do
    Channel.create!(
      channel_type: "whatsapp_cloud",
      identifier: "id-#{SecureRandom.hex(4)}",
      name: "WA"
    ).tap { |c| ChannelTeam.create!(channel: c, team: team) }
  end
  let(:user) { make_user.tap { |u| TeamMember.create!(user: u, team: team) } }

  it "rejects nil user" do
    expect(described_class.allowed?(nil, "conversations:user:1")).to be false
  end

  it "allows personal stream for self" do
    expect(described_class.allowed?(user, "conversations:user:#{user.id}")).to be true
  end

  it "rejects another user's personal stream" do
    other = make_user
    expect(described_class.allowed?(user, "conversations:user:#{other.id}")).to be false
  end

  it "allows channel stream for an accessible channel" do
    expect(described_class.allowed?(user, "conversations:channel:#{channel.id}")).to be true
  end

  it "rejects channel stream for a foreign channel" do
    foreign = Channel.create!(channel_type: "whatsapp_cloud", identifier: "x-#{SecureRandom.hex(4)}", name: "F")
    expect(described_class.allowed?(user, "conversations:channel:#{foreign.id}")).to be false
  end

  it "allows a conversation the user can view (via ConversationPolicy)" do
    contact = Contact.create!(name: "C")
    cc = ContactChannel.create!(channel: channel, contact: contact, source_id: "src-#{SecureRandom.hex(4)}")
    conv = Conversation.create!(
      channel: channel, contact: contact, contact_channel: cc,
      display_id: SecureRandom.random_number(1_000_000) + 1, status: "queued"
    )
    expect(described_class.allowed?(user, "conversation:#{conv.id}")).to be true
  end

  it "rejects unknown stream names" do
    expect(described_class.allowed?(user, "random:42")).to be false
  end
end
