require "rails_helper"

RSpec.describe Assignments::AutoAssign do
  def make_user(availability: "online")
    User.create!(
      name: "U-#{SecureRandom.hex(3)}",
      email_address: "u-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      role: "agent",
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

  let(:team) { Team.create!(name: "T-#{SecureRandom.hex(3)}") }
  let(:channel) do
    Channel.create!(
      channel_type: "whatsapp_cloud",
      identifier: "id-#{SecureRandom.hex(4)}",
      name: "WA",
      auto_assign: true,
      auto_assign_config: {"strategy" => "round_robin", "team_id" => team.id}
    ).tap { |c| ChannelTeam.create!(channel: c, team: team) }
  end
  let!(:agent_a) { make_user.tap { |u| TeamMember.create!(user: u, team: team) } }
  let!(:agent_b) { make_user.tap { |u| TeamMember.create!(user: u, team: team) } }
  let(:conversation) { make_conversation(channel: channel, status: "queued") }

  it "no-ops when channel.auto_assign is false" do
    channel.update!(auto_assign: false)
    described_class.call(conversation)
    expect(conversation.reload.assignee_id).to be_nil
  end

  it "round-robin picks the agent with fewest active assignments" do
    make_conversation(channel: channel, assignee: agent_a, status: "assigned")
    described_class.call(conversation)
    expect(conversation.reload.assignee).to eq(agent_b)
    expect(conversation.status).to eq("assigned")
    expect(conversation.team).to eq(team)
  end

  it "capacity strategy honors max capacity" do
    channel.update!(auto_assign_config: {"strategy" => "capacity", "capacity" => 1, "team_id" => team.id})
    make_conversation(channel: channel, assignee: agent_a, status: "assigned")
    described_class.call(conversation)
    expect(conversation.reload.assignee).to eq(agent_b)
  end

  it "stays queued when no agent is online" do
    User.update_all(availability: "offline")
    described_class.call(conversation)
    expect(conversation.reload).to have_attributes(status: "queued", assignee_id: nil)
  end

  it "emits conversations:assigned" do
    expect { described_class.call(conversation) }
      .to change { Event.where(name: "conversations:assigned", subject: conversation).count }.by(1)
  end

  it "is idempotent — already-assigned conversation is not reassigned" do
    conversation.update!(assignee: agent_a, status: "assigned")
    described_class.call(conversation)
    expect(conversation.reload.assignee).to eq(agent_a)
  end

  it "serializes concurrent picks via advisory lock" do
    conv2 = make_conversation(channel: channel, status: "queued")
    ts = [
      Thread.new { ActiveRecord::Base.connection_pool.with_connection { described_class.call(conversation) } },
      Thread.new { ActiveRecord::Base.connection_pool.with_connection { described_class.call(conv2) } }
    ]
    ts.each(&:join)
    assignees = [conversation.reload.assignee, conv2.reload.assignee]
    expect(assignees.compact.uniq.size).to eq(2)
  end
end
