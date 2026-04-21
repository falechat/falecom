require "spec_helper"
require "json"

RSpec.describe FaleComChannel::DispatchClient do
  let(:container_url) { "http://whatsapp.example.com" }
  let(:secret) { "dispatch-secret" }
  let(:payload) { {"channel_id" => "ch-1", "to" => "+5511999990000", "text" => "Hello"} }

  # Build a Faraday connection backed by the test adapter, with raise_error middleware.
  def build_test_connection(stubs)
    Faraday.new(url: container_url) do |f|
      f.response :raise_error
      f.adapter :test, stubs
    end
  end

  describe "#send_message" do
    it "POSTs JSON to /send" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.post("/send") do |env|
        [200, {"Content-Type" => "application/json"}, JSON.generate({"external_id" => "wamid.123"})]
      end

      client = described_class.new(container_url: container_url, secret: secret,
        connection: build_test_connection(stubs))
      client.send_message(payload)
      stubs.verify_stubbed_calls
    end

    it "request body is JSON.generate(payload) — serialized exactly once (signature must match the body as sent)" do
      captured_body = nil
      captured_sig = nil
      captured_ts = nil

      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.post("/send") do |env|
        captured_body = env.body
        captured_sig = env.request_headers["X-FaleCom-Signature"]
        captured_ts = env.request_headers["X-FaleCom-Timestamp"].to_i
        [200, {"Content-Type" => "application/json"}, "{}"]
      end

      client = described_class.new(container_url: container_url, secret: secret,
        connection: build_test_connection(stubs))
      client.send_message(payload)

      expected_body = JSON.generate(payload)
      expect(captured_body).to eq(expected_body)

      expected_sig = FaleComChannel::HmacSigner.sign(expected_body, secret, timestamp: captured_ts)
      expect(captured_sig).to eq(expected_sig)
    end

    it "request is HMAC-signed with the dispatch secret (separate from ingest)" do
      captured_sig = nil
      captured_ts = nil
      captured_body = nil

      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.post("/send") do |env|
        captured_sig = env.request_headers["X-FaleCom-Signature"]
        captured_ts = env.request_headers["X-FaleCom-Timestamp"].to_i
        captured_body = env.body
        [200, {"Content-Type" => "application/json"}, "{}"]
      end

      client = described_class.new(container_url: container_url, secret: secret,
        connection: build_test_connection(stubs))

      ingest_secret = "ingest-secret-totally-different"
      client.send_message(payload)

      # Signature must verify with dispatch secret, not ingest secret
      expect(FaleComChannel::HmacSigner.sign(captured_body, secret, timestamp: captured_ts)).to eq(captured_sig)
      expect(FaleComChannel::HmacSigner.sign(captured_body, ingest_secret, timestamp: captured_ts)).not_to eq(captured_sig)
    end

    it "request includes Content-Type: application/json" do
      stubs = Faraday::Adapter::Test::Stubs.new
      captured_ct = nil
      stubs.post("/send") do |env|
        captured_ct = env.request_headers["Content-Type"]
        [200, {"Content-Type" => "application/json"}, "{}"]
      end

      client = described_class.new(container_url: container_url, secret: secret,
        connection: build_test_connection(stubs))
      client.send_message(payload)

      expect(captured_ct).to eq("application/json")
    end

    it "request includes X-FaleCom-Timestamp as a unix seconds string" do
      stubs = Faraday::Adapter::Test::Stubs.new
      captured_ts = nil
      stubs.post("/send") do |env|
        captured_ts = env.request_headers["X-FaleCom-Timestamp"]
        [200, {"Content-Type" => "application/json"}, "{}"]
      end

      before_call = Time.now.to_i
      client = described_class.new(container_url: container_url, secret: secret,
        connection: build_test_connection(stubs))
      client.send_message(payload)
      after_call = Time.now.to_i

      ts_int = captured_ts.to_i
      expect(ts_int).to be_between(before_call, after_call)
      expect(captured_ts).to eq(ts_int.to_s)
    end

    it "request includes X-FaleCom-Correlation-Id from Logging.current_correlation_id when set" do
      stubs = Faraday::Adapter::Test::Stubs.new
      captured_cid = nil
      stubs.post("/send") do |env|
        captured_cid = env.request_headers["X-FaleCom-Correlation-Id"]
        [200, {"Content-Type" => "application/json"}, "{}"]
      end

      client = described_class.new(container_url: container_url, secret: secret,
        connection: build_test_connection(stubs))

      FaleComChannel::Logging.with_correlation_id("test-cid-dispatch") do
        client.send_message(payload)
      end

      expect(captured_cid).to eq("test-cid-dispatch")
    end

    it "request generates a fresh uuid for X-FaleCom-Correlation-Id when no correlation id is active" do
      stubs = Faraday::Adapter::Test::Stubs.new
      captured_cid = nil
      stubs.post("/send") do |env|
        captured_cid = env.request_headers["X-FaleCom-Correlation-Id"]
        [200, {"Content-Type" => "application/json"}, "{}"]
      end

      client = described_class.new(container_url: container_url, secret: secret,
        connection: build_test_connection(stubs))

      # Ensure no correlation id is set
      FaleComChannel::Logging.with_correlation_id(nil) do
        client.send_message(payload)
      end

      expect(captured_cid).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    end

    it "returns parsed JSON response body on 200 (e.g. { \"external_id\" => \"wamid...\" })" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.post("/send") do |_env|
        [200, {"Content-Type" => "application/json"}, JSON.generate({"external_id" => "wamid.abc123"})]
      end

      client = described_class.new(container_url: container_url, secret: secret,
        connection: build_test_connection(stubs))
      result = client.send_message(payload)

      expect(result).to eq({"external_id" => "wamid.abc123"})
    end

    it "returns {} on 200 with empty body" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.post("/send") do |_env|
        [200, {"Content-Type" => "application/json"}, ""]
      end

      client = described_class.new(container_url: container_url, secret: secret,
        connection: build_test_connection(stubs))
      result = client.send_message(payload)

      expect(result).to eq({})
    end

    it "does NOT retry on 500 — raises DispatchError on first attempt" do
      call_count = 0
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.post("/send") do |_env|
        call_count += 1
        [500, {"Content-Type" => "application/json"}, JSON.generate({"error" => "upstream down"})]
      end

      client = described_class.new(container_url: container_url, secret: secret,
        connection: build_test_connection(stubs))

      expect { client.send_message(payload) }.to raise_error(FaleComChannel::DispatchError)
      expect(call_count).to eq(1)
    end

    it "raises DispatchError on 422 with status and body in the message" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.post("/send") do |_env|
        [422, {"Content-Type" => "application/json"}, JSON.generate({"error" => "invalid payload"})]
      end

      client = described_class.new(container_url: container_url, secret: secret,
        connection: build_test_connection(stubs))

      expect { client.send_message(payload) }.to raise_error(FaleComChannel::DispatchError) do |err|
        expect(err.message).to include("422")
      end
    end

    it "logs event: \"dispatch_post\" with status and duration on success" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.post("/send") do |_env|
        [200, {"Content-Type" => "application/json"}, JSON.generate({"external_id" => "wamid.x"})]
      end

      client = described_class.new(container_url: container_url, secret: secret,
        connection: build_test_connection(stubs))

      logged = nil
      allow(FaleComChannel.logger).to receive(:info) { |msg| logged = msg }

      client.send_message(payload)

      expect(logged).to be_a(Hash)
      expect(logged[:event]).to eq("dispatch_post")
      expect(logged[:status]).to eq(200)
      expect(logged).to have_key(:duration_ms)
    end

    it "logs event: \"dispatch_post_failed\" on failure" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.post("/send") do |_env|
        [500, {"Content-Type" => "application/json"}, "error"]
      end

      client = described_class.new(container_url: container_url, secret: secret,
        connection: build_test_connection(stubs))

      logged = nil
      allow(FaleComChannel.logger).to receive(:error) { |msg| logged = msg }

      expect { client.send_message(payload) }.to raise_error(FaleComChannel::DispatchError)

      expect(logged).to be_a(Hash)
      expect(logged[:event]).to eq("dispatch_post_failed")
    end
  end
end
