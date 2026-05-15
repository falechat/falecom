require "rails_helper"

RSpec.describe "PATCH /dashboard/users/availability", type: :request do
  include ActiveJob::TestHelper

  let(:team) { Team.create!(name: "T-#{SecureRandom.hex(3)}") }
  let(:channel) do
    Channel.create!(
      channel_type: "whatsapp_cloud",
      identifier: "wa-#{SecureRandom.hex(3)}",
      name: "WA",
      auto_assign: true,
      auto_assign_config: {"strategy" => "round_robin"}
    ).tap { |c| ChannelTeam.create!(channel: c, team: team) }
  end
  let(:agent) do
    User.create!(
      name: "A",
      email_address: "a-#{SecureRandom.hex(4)}@x.test",
      password: "password",
      role: "agent",
      availability: "offline"
    ).tap { |u| TeamMember.create!(user: u, team: team) }
  end
  let!(:queued) do
    contact = Contact.create!(name: "C")
    cc = ContactChannel.create!(channel: channel, contact: contact, source_id: "src-#{SecureRandom.hex(4)}")
    channel.conversations.create!(
      contact: contact, contact_channel: cc, status: "queued",
      display_id: SecureRandom.random_number(1_000_000) + 1, last_activity_at: Time.current
    )
  end

  def sign_in(user)
    post session_path, params: {email_address: user.email_address, password: "password"}
  end

  before { sign_in(agent) }

  it "updates availability and emits users:availability_changed" do
    expect {
      patch dashboard_user_availability_path, params: {availability: "online"}
    }.to change { agent.reload.availability }.from("offline").to("online")
      .and change { Event.where(name: "users:availability_changed", subject: agent).count }.by(1)
  end

  it "enqueues AutoAssignJob for each queued conversation on accessible channels when going online" do
    expect {
      patch dashboard_user_availability_path, params: {availability: "online"}
    }.to have_enqueued_job(AutoAssignJob).with(queued.id)
  end

  it "does not enqueue jobs when going offline or busy" do
    agent.update!(availability: "online")
    expect {
      patch dashboard_user_availability_path, params: {availability: "busy"}
    }.not_to have_enqueued_job(AutoAssignJob)
  end

  it "422s on invalid availability" do
    patch dashboard_user_availability_path, params: {availability: "lol"}
    expect(response).to have_http_status(:unprocessable_content)
  end
end
