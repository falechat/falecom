require "rails_helper"

RSpec.describe Flows::Handoff do
  include ActiveJob::TestHelper

  let(:channel) { Channel.create!(name: "c", channel_type: "whatsapp_cloud", identifier: "c-1", auto_assign: false) }
  let(:contact) { Contact.create!(name: "Provider-Name") }
  let(:cc) { ContactChannel.create!(contact: contact, channel: channel, source_id: "s") }
  let(:conv) { Conversation.create!(channel: channel, contact: contact, contact_channel: cc, display_id: 1, status: "bot") }
  let(:flow) { Flow.create!(name: "f") }
  let(:cf) { ConversationFlow.create!(conversation: conv, flow: flow, status: "active", state: {"contact_name" => "Real Name"}) }
  let(:team) { Team.create!(name: "Vendas").tap { |t| ChannelTeam.create!(channel: channel, team: t) } }
  let(:node) { FlowNode.create!(flow: flow, node_type: "handoff", content: {"team_id" => team.id, "message" => "Transferindo...", "assign_collected_name" => true}) }

  it "sends handoff message + completes flow + queues conversation" do
    expect { described_class.call(conv, cf, node) }
      .to change { conv.reload.status }.from("bot").to("queued")
      .and change { cf.reload.status }.from("active").to("completed")
      .and change { conv.messages.where(direction: "outbound").count }.by(1)
    expect(conv.team).to eq(team)
    expect(cf.reload.current_node).to be_nil
  end

  it "applies assign_collected_name overriding provider-reported name" do
    described_class.call(conv, cf, node)
    expect(contact.reload.name).to eq("Real Name")
  end

  it "skips name override when assign_collected_name false" do
    node.update!(content: node.content.merge("assign_collected_name" => false))
    described_class.call(conv, cf, node)
    expect(contact.reload.name).to eq("Provider-Name")
  end

  it "emits flows:handoff + conversations:status_changed" do
    expect { described_class.call(conv, cf, node) }
      .to change { Event.where(name: "flows:handoff", subject: conv).count }.by(1)
      .and change { Event.where(name: "conversations:status_changed", subject: conv).count }.by(1)
  end

  it "enqueues AutoAssignJob when channel.auto_assign? is true" do
    channel.update!(auto_assign: true)
    expect { described_class.call(conv, cf, node) }.to have_enqueued_job(AutoAssignJob)
  end

  it "no-op message when content has no 'message' key" do
    node.update!(content: {"team_id" => team.id})
    expect { described_class.call(conv, cf, node) }.not_to change { conv.messages.count }
  end
end
