require "rails_helper"

RSpec.describe "Ingestion::ProcessMessage + auto-assign" do
  include ActiveJob::TestHelper

  let(:team) { Team.create!(name: "T-#{SecureRandom.hex(3)}") }
  let(:channel) do
    Channel.create!(
      channel_type: "whatsapp_cloud",
      identifier: "+5511999999999",
      name: "WA",
      auto_assign: true,
      auto_assign_config: {"strategy" => "round_robin"}
    ).tap { |c| ChannelTeam.create!(channel: c, team: team) }
  end

  before { channel }

  it "enqueues AutoAssignJob exactly once for a brand-new queued conversation" do
    payload = PayloadFixtures.inbound_text
    expect {
      Ingestion::ProcessMessage.call(channel, payload)
    }.to have_enqueued_job(AutoAssignJob).exactly(:once)
  end

  it "does NOT re-enqueue for an existing open conversation" do
    payload = PayloadFixtures.inbound_text
    Ingestion::ProcessMessage.call(channel, payload)
    clear_enqueued_jobs
    second = PayloadFixtures.inbound_text(
      "message" => {"external_id" => "WAMID.#{SecureRandom.hex(6)}"}
    )
    Ingestion::ProcessMessage.call(channel, second)
    expect(enqueued_jobs).to be_empty
  end
end
