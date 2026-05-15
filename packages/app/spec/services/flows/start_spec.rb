require "rails_helper"

RSpec.describe Flows::Start do
  let(:channel) { Channel.create!(name: "c", channel_type: "whatsapp_cloud", identifier: "c-1") }
  let(:contact) { Contact.create!(name: "x") }
  let(:cc) { ContactChannel.create!(contact: contact, channel: channel, source_id: "s") }
  let(:conv) { Conversation.create!(channel: channel, contact: contact, contact_channel: cc, display_id: 1, status: "bot") }
  let(:flow) { Flow.create!(name: "f", inactivity_threshold_hours: 24) }
  let!(:root) { FlowNode.create!(flow: flow, node_type: "message", content: {"text" => "Olá"}).tap { |n| flow.update!(root_node: n) } }
  let!(:short) { FlowNode.create!(flow: flow, node_type: "message", content: {"text" => "Bem-vindo de volta"}).tap { |n| flow.update!(short_greeting_node: n) } }

  before { channel.update!(active_flow: flow) }

  it "no-op when channel has no active_flow" do
    channel.update!(active_flow: nil)
    expect { described_class.call(conv) }.not_to change(ConversationFlow, :count)
  end

  it "no-op when active_flow.is_active is false" do
    flow.update!(is_active: false)
    expect { described_class.call(conv) }.not_to change(ConversationFlow, :count)
  end

  it "creates ConversationFlow starting at root_node when no recent activity" do
    described_class.call(conv)
    cf = conv.reload.conversation_flow
    expect(cf).to be_present
  end

  it "starts at short_greeting_node when recent activity exists" do
    prior_conv = Conversation.create!(channel: channel, contact: contact, contact_channel: cc, display_id: 2, status: "resolved")
    Message.create!(conversation: prior_conv, channel: channel, direction: "inbound", content: "oi", content_type: "text", status: "received", created_at: 1.hour.ago)
    described_class.call(conv)
    last_outbound = conv.messages.where(direction: "outbound").order(:created_at).first
    expect(last_outbound.content).to eq("Bem-vindo de volta")
  end

  it "emits flows:started and immediately runs first node" do
    expect { described_class.call(conv) }
      .to change { Event.where(name: "flows:started", subject: conv).count }.by(1)
      .and change { conv.messages.where(direction: "outbound").count }.by_at_least(1)
  end
end
