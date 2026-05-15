require "rails_helper"

RSpec.describe Conversations::Scope do
  def make_user(role: "agent")
    User.create!(
      name: "U-#{SecureRandom.hex(3)}",
      email_address: "u-#{SecureRandom.hex(4)}@x.test",
      password: "password",
      role: role,
      availability: "online"
    )
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

  let(:team_a) { Team.create!(name: "A-#{SecureRandom.hex(2)}") }
  let(:team_b) { Team.create!(name: "B-#{SecureRandom.hex(2)}") }
  let(:channel_a) { make_channel(team: team_a) }
  let(:channel_b) { make_channel(team: team_b) }
  let(:agent) { make_user.tap { |u| TeamMember.create!(user: u, team: team_a) } }
  let(:admin) { make_user(role: "admin") }

  let!(:mine) { make_conv(channel: channel_a, assignee: agent, status: "assigned", team: team_a) }
  let!(:unassigned) { make_conv(channel: channel_a, assignee: nil, status: "queued") }
  let!(:teammates) { make_conv(channel: channel_a, team: team_a, status: "assigned") }
  let!(:foreign) { make_conv(channel: channel_b, status: "queued", team: team_b) }

  it "view=mine returns only assigned-to-me" do
    expect(described_class.call(user: agent, params: {view: "mine"})).to contain_exactly(mine)
  end

  it "view=unassigned returns queued+unassigned on accessible channels" do
    expect(described_class.call(user: agent, params: {view: "unassigned"})).to contain_exactly(unassigned)
  end

  it "view=team returns conversations on agent's teams" do
    expect(described_class.call(user: agent, params: {view: "team"})).to contain_exactly(mine, teammates)
  end

  it "view=channel filters by channel_id" do
    expect(described_class.call(user: agent, params: {view: "channel", channel_id: channel_a.id})).to contain_exactly(mine, unassigned, teammates)
  end

  it "agent cannot see conversations on inaccessible channels under any view" do
    expect(described_class.call(user: agent, params: {view: "team"})).not_to include(foreign)
  end

  it "view=all is admin-only" do
    expect(described_class.call(user: admin, params: {view: "all"})).to include(mine, unassigned, foreign)
    expect(described_class.call(user: agent, params: {view: "all"})).not_to include(foreign)
  end

  it "orders by last_activity_at desc, nulls last" do
    teammates.update!(last_activity_at: 1.hour.ago)
    mine.update!(last_activity_at: Time.current)
    result = described_class.call(user: agent, params: {view: "team"}).to_a
    expect(result.first).to eq(mine)
  end
end
