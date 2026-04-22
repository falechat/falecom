require "spec_helper"

RSpec.describe DevWebhook::App do
  include Rack::Test::Methods

  def app
    DevWebhook::App
  end

  let(:stub_sqs) { Aws::SQS::Client.new(stub_responses: true) }

  before do
    allow(DevWebhook).to receive(:sqs_client).and_return(stub_sqs)
  end

  it "enqueues the raw body to sqs-whatsapp-cloud for POST /webhooks/whatsapp-cloud" do
    stub_sqs.stub_responses(:get_queue_url, queue_url: "http://localstack:4566/000000000000/sqs-whatsapp-cloud")
    stub_sqs.stub_responses(:send_message, message_id: "m-1", md5_of_message_body: "x")

    post "/webhooks/whatsapp-cloud", '{"event":"message"}', {"CONTENT_TYPE" => "application/json"}

    expect(last_response.status).to eq(200)
    body = JSON.parse(last_response.body)
    expect(body).to include("status" => "enqueued", "queue" => "sqs-whatsapp-cloud")
    expect(body["bytes"]).to be_positive

    sent = stub_sqs.api_requests.find { |req| req[:operation_name] == :send_message }
    expect(sent[:params][:message_body]).to eq('{"event":"message"}')
    expect(sent[:params][:queue_url]).to eq("http://localstack:4566/000000000000/sqs-whatsapp-cloud")
  end

  it "routes POST /webhooks/zapi to sqs-zapi" do
    stub_sqs.stub_responses(:get_queue_url, queue_url: "http://localstack:4566/000000000000/sqs-zapi")
    stub_sqs.stub_responses(:send_message, message_id: "m-2", md5_of_message_body: "y")

    post "/webhooks/zapi", "raw=body", {}

    expect(last_response.status).to eq(200)
  end

  it "returns 404 for unknown channel types" do
    post "/webhooks/telegram", "{}", {"CONTENT_TYPE" => "application/json"}
    expect(last_response.status).to eq(404)
    expect(JSON.parse(last_response.body)).to eq({"error" => "unknown_channel_type"})
  end
end
