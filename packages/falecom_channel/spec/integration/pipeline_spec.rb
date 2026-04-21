require "spec_helper"
require "faraday"
require "timeout"

# End-to-end pipeline spec: SQS (stubbed) → Consumer → Payload.validate! →
# IngestClient → Rails (stubbed via Faraday test adapter).
#
# Asserts HMAC signature, correlation-id, and body all flow through every
# module correctly. No live network.

RSpec.describe "ingestion pipeline" do
  let(:secret) { "test-ingest-secret" }
  let(:rails_stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:faraday_conn) do
    Faraday.new do |f|
      f.response :raise_error
      f.request :retry, max: 3, interval: 0, backoff_factor: 0,
        retry_statuses: [500, 502, 503, 504], methods: %i[post]
      f.adapter :test, rails_stubs
    end
  end
  let(:ingest_client) do
    FaleComChannel::IngestClient.new(
      api_url: "http://rails.test",
      secret: secret,
      connection: faraday_conn
    )
  end

  let(:pipeline_container_class) do
    client = ingest_client
    Class.new do
      include FaleComChannel::Consumer

      queue_name "pipeline-test"

      define_method(:ingest_client) { client }

      def handle(body, _headers)
        payload = JSON.parse(body, symbolize_names: true)
        FaleComChannel::Payload.validate!(payload)
        ingest_client.post(payload)
      end
    end
  end

  let(:fixture_body) { JSON.generate(FaleComChannel::Fixtures.inbound_message) }

  # Minimal mock adapter that yields one message then blocks.
  let(:mock_adapter_class) do
    Class.new do
      attr_reader :acked, :nacked

      def initialize(body:)
        @body = body
        @acked = []
        @nacked = []
        @stopped = false
      end

      def consume
        yield(@body, "receipt-1", {}) unless @stopped
        sleep 0.01 until @stopped
      end

      def ack(h) = @acked << h
      def nack(h) = @nacked << h
      def stop! = @stopped = true
    end
  end

  def run_pipeline(container)
    thread = Thread.new { container.start(install_signal_traps: false) }
    # Give the worker up to 2s to pull + post
    Timeout.timeout(2) do
      sleep 0.02 while container.instance_variable_get(:@adapter)&.acked&.empty? &&
          container.instance_variable_get(:@adapter)&.nacked&.empty?
    end
    container.shutdown!
    thread.join(2)
  end

  it "delivers a valid message to /internal/ingest with correct HMAC and correlation id, then acks" do
    captured = {}
    rails_stubs.post("/internal/ingest") do |env|
      captured[:body] = env.body
      captured[:headers] = env.request_headers.to_h
      [200, {"Content-Type" => "application/json"}, JSON.generate("message_id" => 42)]
    end

    adapter = mock_adapter_class.new(body: fixture_body)
    container = pipeline_container_class.new
    allow(container).to receive(:build_adapter).and_return(adapter)

    run_pipeline(container)

    expect(adapter.acked).to eq(["receipt-1"])
    expect(adapter.nacked).to be_empty

    expect(captured[:body]).to eq(fixture_body)

    headers = captured[:headers].transform_keys(&:downcase)
    ts = headers["x-falecom-timestamp"].to_i
    expected_sig = FaleComChannel::HmacSigner.sign(fixture_body, secret, timestamp: ts)
    expect(headers["x-falecom-signature"]).to eq(expected_sig)

    cid = headers["x-falecom-correlation-id"]
    expect(cid).to match(/\A[0-9a-f-]{36}\z/i)
  end

  it "nacks when /internal/ingest returns 500 repeatedly" do
    attempts = 0
    rails_stubs.post("/internal/ingest") do |_env|
      attempts += 1
      [500, {}, "boom"]
    end

    adapter = mock_adapter_class.new(body: fixture_body)
    container = pipeline_container_class.new
    allow(container).to receive(:build_adapter).and_return(adapter)

    run_pipeline(container)

    expect(adapter.nacked).to eq(["receipt-1"])
    expect(adapter.acked).to be_empty
    expect(attempts).to be >= 4 # 1 initial + 3 retries
  end
end
