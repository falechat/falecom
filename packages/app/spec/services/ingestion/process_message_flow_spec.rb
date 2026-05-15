require "rails_helper"

RSpec.describe "Ingestion::ProcessMessage flow integration" do
  include ActiveJob::TestHelper

  let(:flow) { Flow.create!(name: "f") }
  let!(:root) do
    node = FlowNode.create!(flow: flow, node_type: "menu",
      content: {"text" => "?", "options" => [{"key" => "1", "label" => "x", "next_node_id" => nil}]})
    flow.update!(root_node: node)
    node
  end
  let(:flow_channel) do
    Channel.create!(name: "c", channel_type: "whatsapp_cloud", identifier: "c-flow", active_flow: flow)
  end

  def payload(channel:, content: "Oi", source_id: SecureRandom.hex(4))
    {
      "type" => "inbound_message",
      "channel" => {"type" => channel.channel_type, "identifier" => channel.identifier},
      "contact" => {"source_id" => source_id, "name" => "Customer"},
      "message" => {"external_id" => SecureRandom.hex(6), "content" => content, "content_type" => "text"},
      "metadata" => {}
    }
  end

  before { stub_dispatch_client }

  it "calls Flows::Start when conversation_flow is nil + status bot" do
    expect(Flows::Start).to receive(:call).and_call_original
    Ingestion::ProcessMessage.call(flow_channel, payload(channel: flow_channel))
  end

  it "calls Flows::Advance on subsequent inbound messages" do
    Ingestion::ProcessMessage.call(flow_channel, payload(channel: flow_channel, source_id: "55119"))
    expect(Flows::Advance).to receive(:call).and_call_original
    Ingestion::ProcessMessage.call(flow_channel, payload(channel: flow_channel, source_id: "55119", content: "1"))
  end

  it "skips flow engine when channel has no active_flow" do
    bare = Channel.create!(name: "bare", channel_type: "whatsapp_cloud", identifier: "bare-1")
    expect(Flows::Start).not_to receive(:call)
    expect(Flows::Advance).not_to receive(:call)
    Ingestion::ProcessMessage.call(bare, payload(channel: bare))
  end

  it "does NOT enqueue AutoAssignJob for new bot conversations on flow channels" do
    expect {
      Ingestion::ProcessMessage.call(flow_channel, payload(channel: flow_channel))
    }.not_to have_enqueued_job(AutoAssignJob)
  end

  it "still enqueues AutoAssignJob for new queued conversations on non-flow channels" do
    bare = Channel.create!(name: "bare2", channel_type: "whatsapp_cloud", identifier: "bare-2",
      auto_assign: true, auto_assign_config: {"strategy" => "round_robin"})
    ChannelTeam.create!(channel: bare, team: Team.create!(name: "T"))
    expect {
      Ingestion::ProcessMessage.call(bare, payload(channel: bare))
    }.to have_enqueued_job(AutoAssignJob)
  end
end
