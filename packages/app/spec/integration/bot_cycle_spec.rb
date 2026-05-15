require "rails_helper"

RSpec.describe "Bot cycle (inbound -> bot -> handoff -> auto-assign)", integration: true do
  include ActiveJob::TestHelper

  let!(:vendas) { Team.create!(name: "Vendas") }
  let!(:agent) do
    User.create!(name: "Agent", email_address: "a@example.com", password: "abcdef12",
      role: "agent", availability: "online").tap { |u| TeamMember.create!(user: u, team: vendas) }
  end
  let!(:channel) do
    Channel.create!(name: "wa", channel_type: "whatsapp_cloud", identifier: "wa-flow",
      auto_assign: true, auto_assign_config: {"strategy" => "round_robin"})
      .tap { |c| ChannelTeam.create!(channel: c, team: vendas) }
  end

  let!(:flow) { Flow.create!(name: "Atendimento") }
  let!(:greeting) { FlowNode.create!(flow: flow, node_type: "message", content: {"text" => "Olá!"}) }
  let!(:ask) { FlowNode.create!(flow: flow, node_type: "collect", content: {"text" => "Nome?", "variable" => "contact_name", "validation" => "any"}) }
  let!(:handoff_node) { FlowNode.create!(flow: flow, node_type: "handoff", content: {"team_id" => vendas.id, "message" => "Transferindo...", "assign_collected_name" => true}) }
  let!(:menu) { FlowNode.create!(flow: flow, node_type: "menu", content: {"text" => "Como ajudar?", "options" => [{"key" => "1", "label" => "Vendas", "next_node_id" => handoff_node.id}]}) }

  before do
    greeting.update!(next_node: ask)
    ask.update!(next_node: menu)
    flow.update!(root_node: greeting)
    channel.update!(active_flow: flow)
    stub_dispatch_client
  end

  def payload(content, source_id: "55119")
    {
      "type" => "inbound_message",
      "channel" => {"type" => channel.channel_type, "identifier" => channel.identifier},
      "contact" => {"source_id" => source_id, "name" => "Provider"},
      "message" => {"external_id" => SecureRandom.hex(6), "content" => content, "content_type" => "text"},
      "metadata" => {}
    }
  end

  it "runs the full cycle: greeting -> collect -> menu -> handoff -> auto-assign" do
    perform_enqueued_jobs do
      Ingestion::ProcessMessage.call(channel, payload("Oi"))
      conv = Conversation.last
      expect(conv.status).to eq("bot")
      expect(conv.messages.where(direction: "outbound").count).to be >= 1

      Ingestion::ProcessMessage.call(channel, payload("Maria"))
      Ingestion::ProcessMessage.call(channel, payload("1"))

      conv.reload
      expect(conv.team).to eq(vendas)
      expect(conv.contact.name).to eq("Maria")
      expect(conv.assignee).to eq(agent)
      expect(conv.status).to eq("assigned")
    end
  end
end
