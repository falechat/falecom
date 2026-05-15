require "rails_helper"

RSpec.describe "Dashboard::Flows::Nodes", type: :request do
  def make_user(role: "admin")
    User.create!(name: "U-#{SecureRandom.hex(3)}", email_address: "u-#{SecureRandom.hex(4)}@x.test",
      password: "password", role: role, availability: "online")
  end

  def sign_in(user)
    post session_path, params: {email_address: user.email_address, password: "password"}
  end

  let(:admin) { make_user(role: "admin") }
  let(:flow) { Flow.create!(name: "f") }

  before { sign_in(admin) }

  it "POST creates a message node" do
    expect {
      post dashboard_flow_nodes_path(flow), params: {flow_node: {node_type: "message", content: {text: "Olá"}.to_json}}
    }.to change(FlowNode, :count).by(1)
    expect(FlowNode.last.content).to eq("text" => "Olá")
  end

  it "POST creates a menu with options array" do
    target = FlowNode.create!(flow: flow, node_type: "handoff", content: {a: 1})
    post dashboard_flow_nodes_path(flow), params: {flow_node: {node_type: "menu", content: {
      text: "?",
      options: [{key: "1", label: "Vendas", next_node_id: target.id}]
    }.to_json}}
    n = FlowNode.where(node_type: "menu").last
    expect(n.content["options"].first).to include("key" => "1", "next_node_id" => target.id)
  end

  it "PATCH updates content" do
    n = FlowNode.create!(flow: flow, node_type: "message", content: {"text" => "a"})
    patch dashboard_flow_node_path(flow, n), params: {flow_node: {content: {text: "b"}.to_json}}
    expect(n.reload.content).to eq("text" => "b")
  end

  it "DELETE removes node" do
    n = FlowNode.create!(flow: flow, node_type: "message", content: {"x" => 1})
    expect { delete dashboard_flow_node_path(flow, n) }.to change(FlowNode, :count).by(-1)
  end

  it "DELETE 422 when node is referenced by an active ConversationFlow" do
    n = FlowNode.create!(flow: flow, node_type: "message", content: {"x" => 1})
    channel = Channel.create!(name: "c", channel_type: "whatsapp_cloud", identifier: "c-#{SecureRandom.hex(3)}")
    contact = Contact.create!
    cc = ContactChannel.create!(contact: contact, channel: channel, source_id: "s-#{SecureRandom.hex(3)}")
    conv = Conversation.create!(channel: channel, contact: contact, contact_channel: cc, display_id: rand(1_000_000), status: "bot")
    ConversationFlow.create!(conversation: conv, flow: flow, current_node: n, status: "active")
    delete dashboard_flow_node_path(flow, n)
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "422s on malformed JSON content" do
    post dashboard_flow_nodes_path(flow), params: {flow_node: {node_type: "message", content: "{bad"}}
    expect(response).to have_http_status(:unprocessable_content)
  end
end
