require "spec_helper"
require_relative "../../app"
require "aws-sdk-sqs"
require "openssl"
require "json"
require "timeout"

RSpec.describe "WhatsApp Cloud → Rails pipeline", :e2e do
  let(:app_secret) { "test-app-secret" }
  let(:queue_name) { "sqs-whatsapp-cloud-e2e-#{SecureRandom.hex(4)}" }
  let(:sqs) { Aws::SQS::Client.new(region: "us-east-1") }
  let(:queue_url) { sqs.create_queue(queue_name: queue_name).queue_url }

  before do
    # Allow live HTTP to LocalStack (SQS SDK routes via *.localstack.cloud) and
    # stub the Rails ingest endpoint with WebMock.
    WebMock.disable_net_connect!(allow_localhost: true, allow: /localstack/)

    # Swap in test-friendly env for the gem's Consumer defaults.
    ENV["SQS_QUEUE_NAME"] = queue_name
    ENV["FALECOM_API_URL"] = "http://rails.test"
    ENV["WHATSAPP_APP_SECRET"] = app_secret
    queue_url
  end

  after do
    sqs.delete_queue(queue_url: queue_url)
  rescue Aws::SQS::Errors::ServiceError
    # best-effort cleanup
  ensure
    WebMock.disable_net_connect!
  end

  def sign(body)
    "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", app_secret, body)
  end

  it "ingests a signed Meta webhook end-to-end: SQS → Parser → IngestClient → Rails" do
    webhook = JSON.generate(WhatsappCloud::Fixtures.inbound_text_webhook)

    sqs.send_message(
      queue_url: queue_url,
      message_body: webhook,
      message_attributes: {
        "X-Hub-Signature-256" => {string_value: sign(webhook), data_type: "String"}
      }
    )

    received = nil
    stub_request(:post, "http://rails.test/internal/ingest").with { |req|
      received = JSON.parse(req.body)
      true
    }.to_return(status: 200, body: JSON.generate(status: "ok", message_id: 99))

    container = Class.new(WhatsappCloud::Container).new

    thread = Thread.new { container.start(install_signal_traps: false) }

    Timeout.timeout(8) do
      sleep 0.2 while received.nil?
    end

    container.shutdown!
    thread.join(2)

    expect(received).to include(
      "type" => "inbound_message",
      "channel" => a_hash_including("type" => "whatsapp_cloud")
    )
    expect(received.dig("message", "content")).to eq("Olá, tudo bem?")
    expect(received.dig("message", "content_type")).to eq("text")
  end
end
