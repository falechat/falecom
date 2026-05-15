require "rails_helper"

RSpec.describe ConversationPolicy do
  def make_channel(name: "WA #{SecureRandom.hex(3)}", identifier: "id-#{SecureRandom.hex(4)}", **attrs)
    Channel.create!(channel_type: "whatsapp_cloud", identifier: identifier, name: name, **attrs)
  end

  def make_user(role:, availability: "online")
    User.create!(
      name: "U-#{SecureRandom.hex(3)}",
      email_address: "u-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      role: role,
      availability: availability
    )
  end

  def make_conversation(channel:, status: "queued", assignee: nil, team: nil)
    contact = Contact.create!(name: "C-#{SecureRandom.hex(3)}")
    cc = ContactChannel.create!(channel: channel, contact: contact, source_id: "src-#{SecureRandom.hex(4)}")
    Conversation.create!(
      channel: channel,
      contact: contact,
      contact_channel: cc,
      display_id: SecureRandom.random_number(1_000_000) + 1,
      status: status,
      assignee: assignee,
      team: team
    )
  end

  let(:channel_a) { make_channel }
  let(:channel_b) { make_channel }
  let(:team) { Team.create!(name: "T-#{SecureRandom.hex(3)}") }
  let(:other_team) { Team.create!(name: "T-#{SecureRandom.hex(3)}") }
  before do
    ChannelTeam.create!(channel: channel_a, team: team)
    ChannelTeam.create!(channel: channel_b, team: other_team)
  end

  let(:agent) { make_user(role: "agent").tap { |u| TeamMember.create!(user: u, team: team) } }
  let(:supervisor) { make_user(role: "supervisor").tap { |u| TeamMember.create!(user: u, team: team) } }
  let(:admin) { make_user(role: "admin") }

  let(:my_conv) { make_conversation(channel: channel_a, assignee: agent, team: team, status: "assigned") }
  let(:other_conv) { make_conversation(channel: channel_a, status: "queued") }
  let(:foreign_conv) { make_conversation(channel: channel_b, status: "queued") }

  describe "#can_view?" do
    it("agent sees own channel") { expect(described_class.new(agent, my_conv).can_view?).to be true }
    it("agent sees teammates") { expect(described_class.new(agent, other_conv).can_view?).to be true }
    it("agent blind to other team") { expect(described_class.new(agent, foreign_conv).can_view?).to be false }
    it("admin sees everything") { expect(described_class.new(admin, foreign_conv).can_view?).to be true }
  end

  describe "#can_reply?" do
    it("only when assigned") { expect(described_class.new(agent, my_conv).can_reply?).to be true }
    it("not when unassigned") { expect(described_class.new(agent, other_conv).can_reply?).to be false }
    it("admin still needs assignment") { expect(described_class.new(admin, other_conv).can_reply?).to be false }
  end

  describe "#can_pickup?" do
    it("yes on queued unassigned on accessible channel") { expect(described_class.new(agent, other_conv).can_pickup?).to be true }
    it("no on assigned") { expect(described_class.new(agent, my_conv).can_pickup?).to be false }
    it("no on foreign") { expect(described_class.new(agent, foreign_conv).can_pickup?).to be false }
  end

  describe "#can_transfer?" do
    it("agent can transfer own") { expect(described_class.new(agent, my_conv).can_transfer?).to be true }
    it("agent can pickup-transfer") { expect(described_class.new(agent, other_conv).can_transfer?).to be true }
    it("supervisor can transfer any viewable") { expect(described_class.new(supervisor, other_conv).can_transfer?).to be true }
    it("admin unrestricted") { expect(described_class.new(admin, foreign_conv).can_transfer?).to be true }
    it("agent blocked on foreign") { expect(described_class.new(agent, foreign_conv).can_transfer?).to be false }
  end

  describe "#can_resolve?" do
    it("assignee yes") { expect(described_class.new(agent, my_conv).can_resolve?).to be true }
    it("non-assignee no") { expect(described_class.new(agent, other_conv).can_resolve?).to be false }
    it("supervisor yes if viewable") { expect(described_class.new(supervisor, other_conv).can_resolve?).to be true }
    it("admin yes") { expect(described_class.new(admin, foreign_conv).can_resolve?).to be true }
  end
end
