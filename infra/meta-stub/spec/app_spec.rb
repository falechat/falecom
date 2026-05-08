require "spec_helper"

RSpec.describe MetaStub::Server do
  include Rack::Test::Methods

  def app
    described_class.freeze.app
  end

  it "GET /health returns ok" do
    get "/health"
    expect(last_response.status).to eq(200)
    expect(JSON.parse(last_response.body)).to eq({"status" => "ok"})
  end

  it "POST /v21.0/:phone_number_id/messages fakes Meta and returns wamid.test-*" do
    post "/v21.0/PNID/messages", "{}", {"CONTENT_TYPE" => "application/json"}
    expect(last_response.status).to eq(200)
    body = JSON.parse(last_response.body)
    expect(body["messages"].first["id"]).to start_with("wamid.test-")
  end

  it "GET / returns the HTML simulator form" do
    get "/"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include("Meta Stub Simulator")
    expect(last_response.body).to include("/simulate/inbound")
    expect(last_response.body).to include("/simulate/status")
  end

  describe "POST /simulate/inbound" do
    it "forwards a signed Meta inbound webhook to dev-webhook" do
      stub_request(:post, "http://dev-webhook:4000/webhooks/whatsapp-cloud")
        .to_return(status: 200, body: '{"status":"enqueued"}')

      params = {phone_number_id: "PNID", source_id: "55119", content: "oi"}
      post "/simulate/inbound", JSON.generate(params), {"CONTENT_TYPE" => "application/json"}

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body["status"]).to eq("200")
      expect(body.dig("payload", "entry", 0, "changes", 0, "value", "messages", 0, "text", "body")).to eq("oi")
    end
  end

  describe "POST /simulate/status" do
    it "forwards a signed Meta status webhook to dev-webhook" do
      stub_request(:post, "http://dev-webhook:4000/webhooks/whatsapp-cloud")
        .to_return(status: 200, body: '{"status":"enqueued"}')

      params = {phone_number_id: "PNID", external_id: "wamid.A", status: "read"}
      post "/simulate/status", JSON.generate(params), {"CONTENT_TYPE" => "application/json"}

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body.dig("payload", "entry", 0, "changes", 0, "value", "statuses", 0, "status")).to eq("read")
    end
  end
end
