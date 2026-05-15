require "rails_helper"

RSpec.describe Assignments::Transfer do
  include ActiveJob::TestHelper

  def make_user(role: "agent", availability: "online")
    User.create!(
      name: "U-#{SecureRandom.hex(3)}",
      email_address: "u-#{SecureRandom.hex(4)}@x.test",
      password: "password",
      role: role,
      availability: availability
    )
  end

  def make_channel(auto_assign: true)
    Channel.create!(
      channel_type: "whatsapp_cloud",
      identifier: "id-#{SecureRandom.hex(4)}",
      name: "WA",
      auto_assign: auto_assign,
      auto_assign_config: {"strategy" => "round_robin"}
    )
  end

  def make_conversation(channel:, team:, assignee: nil, status: "queued")
    contact = Contact.create!(name: "C-#{SecureRandom.hex(3)}")
    cc = ContactChannel.create!(channel: channel, contact: contact, source_id: "src-#{SecureRandom.hex(4)}")
    Conversation.create!(
      channel: channel, contact: contact, contact_channel: cc,
      display_id: SecureRandom.random_number(1_000_000) + 1,
      status: status, assignee: assignee, team: team
    )
  end

  let(:team_a) { Team.create!(name: "A-#{SecureRandom.hex(3)}") }
  let(:team_b) { Team.create!(name: "B-#{SecureRandom.hex(3)}") }
  let(:channel) do
    make_channel.tap do |c|
      ChannelTeam.create!(channel: c, team: team_a)
      ChannelTeam.create!(channel: c, team: team_b)
    end
  end
  let(:user_a) { make_user.tap { |u| TeamMember.create!(user: u, team: team_a) } }
  let(:user_b) { make_user.tap { |u| TeamMember.create!(user: u, team: team_b) } }
  let(:admin)  { make_user(role: "admin") }
  let(:conversation) { make_conversation(channel: channel, team: team_a, assignee: user_a, status: "assigned") }

  describe "reassign (to_user only)" do
    let!(:user_a2) { make_user.tap { |u| TeamMember.create!(user: u, team: team_a) } }

    it "updates assignee, keeps team, status assigned" do
      described_class.call(conversation: conversation, to_user: user_a2, actor: user_a)
      expect(conversation.reload).to have_attributes(assignee: user_a2, team: team_a, status: "assigned")
    end

    it "emits conversations:transferred" do
      expect {
        described_class.call(conversation: conversation, to_user: user_a2, actor: user_a)
      }.to change { Event.where(name: "conversations:transferred", subject: conversation).count }.by(1)
    end
  end

  describe "team transfer (to_team only)" do
    it "moves team, clears assignee, status queued, enqueues AutoAssignJob" do
      expect {
        described_class.call(conversation: conversation, to_team: team_b, actor: admin)
      }.to have_enqueued_job(AutoAssignJob).with(conversation.id)
      expect(conversation.reload).to have_attributes(team: team_b, assignee_id: nil, status: "queued")
    end

    it "rejects target team that doesn't attend the channel" do
      orphan = Team.create!(name: "orphan-#{SecureRandom.hex(3)}")
      expect {
        described_class.call(conversation: conversation, to_team: orphan, actor: admin)
      }.to raise_error(FaleCom::ValidationError, /does not attend/i)
    end
  end

  describe "team transfer + assign" do
    it "moves and assigns" do
      described_class.call(conversation: conversation, to_team: team_b, to_user: user_b, actor: admin)
      expect(conversation.reload).to have_attributes(team: team_b, assignee: user_b, status: "assigned")
    end

    it "rejects when user not member of target team" do
      expect {
        described_class.call(conversation: conversation, to_team: team_b, to_user: user_a, actor: admin)
      }.to raise_error(FaleCom::ValidationError, /not a member/i)
    end
  end

  describe "unassign" do
    it "clears assignee, keeps team, queued, no auto-enqueue" do
      expect {
        described_class.call(conversation: conversation, actor: user_a)
      }.not_to have_enqueued_job(AutoAssignJob)
      expect(conversation.reload).to have_attributes(team: team_a, assignee_id: nil, status: "queued")
    end
  end

  describe "note" do
    it "creates a system message" do
      expect {
        described_class.call(conversation: conversation, to_user: user_a, actor: user_a, note: "FYI angry")
      }.to change { conversation.messages.count }.by(1)
      msg = conversation.messages.order(:created_at).last
      expect(msg).to have_attributes(content: "FYI angry", sender: nil, direction: "outbound", status: "received")
    end

    it "does NOT enqueue SendMessageJob" do
      expect {
        described_class.call(conversation: conversation, to_user: user_a, actor: user_a, note: "x")
      }.not_to have_enqueued_job(SendMessageJob)
    end
  end

  describe "authorization" do
    it "raises when actor cannot transfer" do
      stranger = make_user
      expect {
        described_class.call(conversation: conversation, to_user: user_a, actor: stranger)
      }.to raise_error(FaleCom::AuthorizationError)
    end
  end
end
