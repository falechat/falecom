require "rails_helper"

RSpec.describe Flows::Advance do
  include ActiveJob::TestHelper

  let(:channel) { Channel.create!(name: "c", channel_type: "whatsapp_cloud", identifier: "c-1") }
  let(:contact) { Contact.create!(name: "x") }
  let(:cc) { ContactChannel.create!(contact: contact, channel: channel, source_id: "s") }
  let(:conv) { Conversation.create!(channel: channel, contact: contact, contact_channel: cc, display_id: 1, status: "bot") }
  let(:flow) { Flow.create!(name: "f") }

  describe "message node" do
    let(:n2) { FlowNode.create!(flow: flow, node_type: "menu", content: {"text" => "?", "options" => [{"key" => "1", "label" => "x", "next_node_id" => nil}]}) }
    let(:msg) { FlowNode.create!(flow: flow, node_type: "message", content: {"text" => "olá"}, next_node: n2) }
    let!(:cf) { ConversationFlow.create!(conversation: conv, flow: flow, current_node: msg, status: "active") }

    it "sends text + advances to next node + emits flows:advanced" do
      expect { described_class.call(conv, nil) }
        .to change { conv.messages.where(direction: "outbound").count }.by_at_least(1)
        .and change { Event.where(name: "flows:advanced", subject: conv).count }.by(1)
      expect(cf.reload.current_node).to eq(n2)
    end
  end

  describe "menu node" do
    let(:vendas) { FlowNode.create!(flow: flow, node_type: "handoff", content: {"team_id" => nil}) }
    let(:menu) { FlowNode.create!(flow: flow, node_type: "menu", content: {"text" => "?", "options" => [{"key" => "1", "label" => "Vendas", "next_node_id" => nil}]}) }

    before do
      menu.content["options"][0]["next_node_id"] = vendas.id
      menu.save!
      ConversationFlow.create!(conversation: conv, flow: flow, current_node: menu, status: "active")
    end

    it "first hit (inbound_message: nil) sends menu, does NOT emit flows:advanced" do
      expect { described_class.call(conv, nil) }.to change { conv.messages.where(direction: "outbound").count }.by(1)
      expect(Event.where(name: "flows:advanced", subject: conv).count).to eq(0)
    end

    it "valid selection advances + emits" do
      inbound = Message.create!(conversation: conv, channel: channel, direction: "inbound", content: "1", content_type: "text", status: "received")
      expect { described_class.call(conv, inbound) }
        .to change { Event.where(name: "flows:advanced", subject: conv).count }.by(1)
    end

    it "invalid selection re-sends menu, NO flows:advanced" do
      inbound = Message.create!(conversation: conv, channel: channel, direction: "inbound", content: "xxx", content_type: "text", status: "received")
      expect { described_class.call(conv, inbound) }.to change { conv.messages.where(direction: "outbound").count }.by(1)
      expect(Event.where(name: "flows:advanced", subject: conv).count).to eq(0)
    end
  end

  describe "collect node" do
    let(:next_n) { FlowNode.create!(flow: flow, node_type: "message", content: {"text" => "ok"}) }
    let(:coll) { FlowNode.create!(flow: flow, node_type: "collect", content: {"text" => "nome?", "variable" => "contact_name", "validation" => "any"}, next_node: next_n) }
    let!(:cf) { ConversationFlow.create!(conversation: conv, flow: flow, current_node: coll, status: "active") }

    it "first hit sends prompt, no advance" do
      expect { described_class.call(conv, nil) }
        .to change { conv.messages.where(direction: "outbound").count }.by(1)
      expect(cf.reload.current_node).to eq(coll)
    end

    it "valid input stores in state, advances" do
      inbound = Message.create!(conversation: conv, channel: channel, direction: "inbound", content: "Maria", content_type: "text", status: "received")
      described_class.call(conv, inbound)
      expect(cf.reload.state["contact_name"]).to eq("Maria")
      # After auto-chain runs the next_n message node, current_node ends at nil
      expect(conv.messages.where(direction: "outbound").order(:created_at).last.content).to eq("ok")
    end

    it "invalid (email validator + non-email) re-prompts, no advance" do
      coll.update!(content: coll.content.merge("validation" => "email"))
      inbound = Message.create!(conversation: conv, channel: channel, direction: "inbound", content: "not-email", content_type: "text", status: "received")
      expect { described_class.call(conv, inbound) }
        .to change { conv.messages.where(direction: "outbound").count }.by(1)
      expect(cf.reload.current_node).to eq(coll)
    end
  end

  describe "branch node" do
    let(:a) { FlowNode.create!(flow: flow, node_type: "message", content: {"text" => "A"}) }
    let(:b) { FlowNode.create!(flow: flow, node_type: "message", content: {"text" => "B"}) }
    let(:branch) { FlowNode.create!(flow: flow, node_type: "branch", content: {"variable" => "dept", "conditions" => [{"value" => "vendas", "next_node_id" => nil}], "default_next_node_id" => nil}) }
    let!(:cf) { ConversationFlow.create!(conversation: conv, flow: flow, current_node: branch, status: "active", state: {"dept" => "vendas"}) }

    before do
      branch.content["conditions"][0]["next_node_id"] = a.id
      branch.content["default_next_node_id"] = b.id
      branch.save!
    end

    it "routes via matching condition" do
      described_class.call(conv, nil)
      # auto-chain runs the message node a -> sends "A"
      expect(conv.messages.where(direction: "outbound").pluck(:content)).to include("A")
    end

    it "falls back to default when no match" do
      cf.update!(state: {"dept" => "other"})
      described_class.call(conv, nil)
      expect(conv.messages.where(direction: "outbound").pluck(:content)).to include("B")
    end
  end

  describe "handoff node" do
    let(:hand) { FlowNode.create!(flow: flow, node_type: "handoff", content: {"team_id" => nil}) }
    let!(:cf) { ConversationFlow.create!(conversation: conv, flow: flow, current_node: hand, status: "active") }

    it "delegates to Flows::Handoff" do
      expect(Flows::Handoff).to receive(:call).with(conv, cf, hand)
      described_class.call(conv, nil)
    end
  end

  describe "infinite loop guard" do
    let!(:a) { FlowNode.create!(flow: flow, node_type: "message", content: {"text" => "a"}) }
    let!(:b) { FlowNode.create!(flow: flow, node_type: "message", content: {"text" => "b"}, next_node: a) }

    before do
      a.update!(next_node: b)
      ConversationFlow.create!(conversation: conv, flow: flow, current_node: a, status: "active")
    end

    it "abandons after MAX_STEPS_PER_ADVANCE" do
      expect { described_class.call(conv, nil) }
        .to change { conv.reload.status }.from("bot").to("queued")
        .and change { Event.where(name: "flows:abandoned", subject: conv).count }.by(1)
    end
  end

  describe "missing / dead conversation_flow" do
    it "restarts flow when conversation_flow is nil and channel has active_flow" do
      flow2 = Flow.create!(name: "f2")
      root = FlowNode.create!(flow: flow2, node_type: "message", content: {"text" => "hi"})
      flow2.update!(root_node: root)
      channel.update!(active_flow: flow2)
      expect(Flows::Start).to receive(:call).with(conv)
      described_class.call(conv, nil)
    end
  end
end
