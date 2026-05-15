require "rails_helper"

RSpec.describe "Dashboard::Flows", type: :request do
  def make_user(role: "agent")
    User.create!(name: "U-#{SecureRandom.hex(3)}", email_address: "u-#{SecureRandom.hex(4)}@x.test",
      password: "password", role: role, availability: "online")
  end

  def sign_in(user)
    post session_path, params: {email_address: user.email_address, password: "password"}
  end

  let(:admin) { make_user(role: "admin") }
  let(:agent) { make_user(role: "agent") }

  describe "as admin" do
    before { sign_in(admin) }

    it "GET index lists flows" do
      Flow.create!(name: "Atendimento")
      get dashboard_flows_path
      expect(response.body).to include("Atendimento")
    end

    it "POST creates a flow" do
      expect { post dashboard_flows_path, params: {flow: {name: "Sales", description: "x"}} }
        .to change(Flow, :count).by(1)
    end

    it "PATCH updates flow metadata" do
      f = Flow.create!(name: "f")
      patch dashboard_flow_path(f), params: {flow: {name: "Renamed", inactivity_threshold_hours: 12}}
      expect(f.reload).to have_attributes(name: "Renamed", inactivity_threshold_hours: 12)
    end

    it "DELETE removes flow when no channel binds it" do
      f = Flow.create!(name: "f")
      delete dashboard_flow_path(f)
      expect(Flow.exists?(f.id)).to be false
    end

    it "DELETE 422 when a channel uses it" do
      f = Flow.create!(name: "f")
      Channel.create!(name: "c", channel_type: "whatsapp_cloud", identifier: "c-#{SecureRandom.hex(3)}", active_flow: f)
      delete dashboard_flow_path(f)
      expect(response).to have_http_status(:unprocessable_content)
      expect(Flow.exists?(f.id)).to be true
    end

    it "GET show renders the form and node form partials" do
      f = Flow.create!(name: "Show me")
      FlowNode.create!(flow: f, node_type: "message", content: {"text" => "hi"})
      get dashboard_flow_path(f)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Show me")
      expect(response.body).to include("node-type-swap")
    end

    it "PATCH set_root re-points root_node_id" do
      f = Flow.create!(name: "f")
      n = FlowNode.create!(flow: f, node_type: "message", content: {"text" => "x"})
      patch set_root_dashboard_flow_path(f), params: {node_id: n.id}
      expect(f.reload.root_node).to eq(n)
    end
  end

  describe "as non-admin" do
    before { sign_in(agent) }
    it "403s" do
      get dashboard_flows_path
      expect(response).to have_http_status(:forbidden)
    end
  end
end
