require "spec_helper"
require "json"

RSpec.describe FaleComChannel::IngestClient do
  let(:api_url) { "http://rails.example.com" }
  let(:payload) { {"channel_id" => "ch-1", "event" => "message_received", "external_id" => "ext-1"} }

  # Build a Faraday connection backed by the test adapter WITH retry middleware active.
  #
  # Middleware order: raise_error BEFORE retry in builder so that retry is the outermost wrapper.
  # In Faraday's stack: retry wraps raise_error wraps adapter.
  # On response path: adapter → raise_error → retry (retry catches and decides whether to re-attempt).
  def build_test_connection(stubs, retry_options: nil)
    opts = retry_options || {max: 3, interval: 0, backoff_factor: 1, retry_statuses: [500, 502, 503, 504], methods: %i[post get]}
    Faraday.new(url: api_url) do |f|
      f.response :raise_error
      f.request :retry, **opts
      f.adapter :test, stubs
    end
  end

  describe "#post" do
    it "POSTs JSON to /internal/ingest with the given payload" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.post("/internal/ingest") do |_env|
        [200, {"Content-Type" => "application/json"}, JSON.generate({"ok" => true})]
      end

      client = described_class.new(api_url: api_url, connection: build_test_connection(stubs))
      client.post(payload)
      stubs.verify_stubbed_calls
    end

    it "request body is JSON.generate(payload)" do
      captured_body = nil

      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.post("/internal/ingest") do |env|
        captured_body = env.body
        [200, {"Content-Type" => "application/json"}, "{}"]
      end

      client = described_class.new(api_url: api_url, connection: build_test_connection(stubs))
      client.post(payload)

      expect(captured_body).to eq(JSON.generate(payload))
    end

    it "request includes Content-Type: application/json" do
      stubs = Faraday::Adapter::Test::Stubs.new
      captured_ct = nil
      stubs.post("/internal/ingest") do |env|
        captured_ct = env.request_headers["Content-Type"]
        [200, {"Content-Type" => "application/json"}, "{}"]
      end

      client = described_class.new(api_url: api_url, connection: build_test_connection(stubs))
      client.post(payload)

      expect(captured_ct).to eq("application/json")
    end

    it "does NOT send HMAC signature or timestamp headers — /internal/ingest is unauthenticated at app layer" do
      captured_headers = nil
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.post("/internal/ingest") do |env|
        captured_headers = env.request_headers.to_h.transform_keys(&:downcase)
        [200, {"Content-Type" => "application/json"}, "{}"]
      end

      client = described_class.new(api_url: api_url, connection: build_test_connection(stubs))
      client.post(payload)

      expect(captured_headers).not_to have_key("x-falecom-signature")
      expect(captured_headers).not_to have_key("x-falecom-timestamp")
    end

    it "request includes X-FaleCom-Correlation-Id from Logging.current_correlation_id when set" do
      stubs = Faraday::Adapter::Test::Stubs.new
      captured_cid = nil
      stubs.post("/internal/ingest") do |env|
        captured_cid = env.request_headers["X-FaleCom-Correlation-Id"]
        [200, {"Content-Type" => "application/json"}, "{}"]
      end

      client = described_class.new(api_url: api_url, connection: build_test_connection(stubs))

      FaleComChannel::Logging.with_correlation_id("test-cid-ingest") do
        client.post(payload)
      end

      expect(captured_cid).to eq("test-cid-ingest")
    end

    it "request generates a fresh uuid for X-FaleCom-Correlation-Id when no correlation id is active" do
      stubs = Faraday::Adapter::Test::Stubs.new
      captured_cid = nil
      stubs.post("/internal/ingest") do |env|
        captured_cid = env.request_headers["X-FaleCom-Correlation-Id"]
        [200, {"Content-Type" => "application/json"}, "{}"]
      end

      client = described_class.new(api_url: api_url, connection: build_test_connection(stubs))

      FaleComChannel::Logging.with_correlation_id(nil) do
        client.post(payload)
      end

      expect(captured_cid).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    end

    it "returns the parsed JSON response body on 200" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.post("/internal/ingest") do |_env|
        [200, {"Content-Type" => "application/json"}, JSON.generate({"ingested" => true, "id" => 42})]
      end

      client = described_class.new(api_url: api_url, connection: build_test_connection(stubs))
      result = client.post(payload)

      expect(result).to eq({"ingested" => true, "id" => 42})
    end

    it "returns {} on 200 with empty body" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.post("/internal/ingest") do |_env|
        [200, {"Content-Type" => "application/json"}, ""]
      end

      client = described_class.new(api_url: api_url, connection: build_test_connection(stubs))
      result = client.post(payload)

      expect(result).to eq({})
    end

    it "retries on 500 — three stubbed 500s then a 200 → succeeds" do
      call_count = 0
      responses = [
        [500, {"Content-Type" => "application/json"}, "error"],
        [500, {"Content-Type" => "application/json"}, "error"],
        [500, {"Content-Type" => "application/json"}, "error"],
        [200, {"Content-Type" => "application/json"}, JSON.generate({"ok" => true})]
      ]

      stubs = Faraday::Adapter::Test::Stubs.new
      responses.each do |resp|
        stubs.post("/internal/ingest") do |_env|
          call_count += 1
          resp
        end
      end

      client = described_class.new(api_url: api_url, connection: build_test_connection(stubs))
      result = client.post(payload)

      expect(result).to eq({"ok" => true})
      expect(call_count).to eq(4)
    end

    it "does NOT retry on 422 → raises IngestError immediately" do
      call_count = 0
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.post("/internal/ingest") do |_env|
        call_count += 1
        [422, {"Content-Type" => "application/json"}, JSON.generate({"error" => "validation failed"})]
      end

      client = described_class.new(api_url: api_url, connection: build_test_connection(stubs))

      expect { client.post(payload) }.to raise_error(FaleComChannel::IngestError)
      expect(call_count).to eq(1)
    end

    it "raises IngestError after retries are exhausted on persistent 5xx" do
      call_count = 0
      stubs = Faraday::Adapter::Test::Stubs.new
      # 4 posts: initial + 3 retries
      4.times do
        stubs.post("/internal/ingest") do |_env|
          call_count += 1
          [500, {"Content-Type" => "application/json"}, "server error"]
        end
      end

      client = described_class.new(api_url: api_url, connection: build_test_connection(stubs))

      expect { client.post(payload) }.to raise_error(FaleComChannel::IngestError)
      expect(call_count).to eq(4)
    end

    it "logs event: \"ingest_post\" with status and duration on success" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.post("/internal/ingest") do |_env|
        [200, {"Content-Type" => "application/json"}, JSON.generate({"ok" => true})]
      end

      client = described_class.new(api_url: api_url, connection: build_test_connection(stubs))

      logged = nil
      allow(FaleComChannel.logger).to receive(:info) { |msg| logged = msg }

      client.post(payload)

      expect(logged).to be_a(Hash)
      expect(logged[:event]).to eq("ingest_post")
      expect(logged[:status]).to eq(200)
      expect(logged).to have_key(:duration_ms)
    end

    it "logs event: \"ingest_post_failed\" on failure" do
      stubs = Faraday::Adapter::Test::Stubs.new
      4.times do
        stubs.post("/internal/ingest") do |_env|
          [500, {"Content-Type" => "application/json"}, "error"]
        end
      end

      client = described_class.new(api_url: api_url, connection: build_test_connection(stubs))

      logged = nil
      allow(FaleComChannel.logger).to receive(:error) { |msg| logged = msg }

      expect { client.post(payload) }.to raise_error(FaleComChannel::IngestError)

      expect(logged).to be_a(Hash)
      expect(logged[:event]).to eq("ingest_post_failed")
    end
  end
end
