require "spec_helper"
require "rack/test"
require "json"
require "falecom_channel/send_server"

# A concrete subclass used by all send_server specs.
class TestSendServer < FaleComChannel::SendServer
  dispatch_secret "test-secret"

  def handle_send(payload)
    {external_id: "wamid-test-#{payload.message.internal_id}"}
  end
end

RSpec.describe FaleComChannel::SendServer do
  include Rack::Test::Methods

  def app
    TestSendServer
  end

  # Compute HMAC signature and POST the body to /send.
  def post_signed(path, body_hash, extra_headers: {})
    raw = JSON.generate(body_hash)
    ts = Time.now.to_i
    sig = FaleComChannel::HmacSigner.sign(raw, "test-secret", timestamp: ts)
    headers = {
      "CONTENT_TYPE" => "application/json",
      "HTTP_X_FALECOM_SIGNATURE" => sig,
      "HTTP_X_FALECOM_TIMESTAMP" => ts.to_s
    }.merge(extra_headers)
    post path, raw, headers
  end

  let(:valid_body) { FaleComChannel::Fixtures.outbound_message }

  # ── Health endpoint ──────────────────────────────────────────────────────────

  describe "GET /health" do
    it "returns 200 with {\"status\":\"ok\"} and requires no signature" do
      get "/health"
      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)).to eq({"status" => "ok"})
    end
  end

  # ── Happy path ───────────────────────────────────────────────────────────────

  describe "POST /send" do
    it "with valid signature and valid payload invokes #handle_send and returns its result as JSON" do
      post_signed("/send", valid_body)
      expect(last_response.status).to eq(200)
      result = JSON.parse(last_response.body, symbolize_names: true)
      expect(result[:external_id]).to eq("wamid-test-12345")
    end

    # ── Auth error paths ─────────────────────────────────────────────────────

    it "without X-FaleCom-Signature returns 401 with {\"error\":\"Missing signature header\"}" do
      raw = JSON.generate(valid_body)
      ts = Time.now.to_i
      post "/send", raw, "CONTENT_TYPE" => "application/json", "HTTP_X_FALECOM_TIMESTAMP" => ts.to_s
      expect(last_response.status).to eq(401)
      expect(JSON.parse(last_response.body)).to eq({"error" => "Missing signature header"})
    end

    it "without X-FaleCom-Timestamp returns 401 with {\"error\":\"Missing timestamp header\"}" do
      raw = JSON.generate(valid_body)
      sig = FaleComChannel::HmacSigner.sign(raw, "test-secret", timestamp: Time.now.to_i)
      post "/send", raw, "CONTENT_TYPE" => "application/json", "HTTP_X_FALECOM_SIGNATURE" => sig
      expect(last_response.status).to eq(401)
      expect(JSON.parse(last_response.body)).to eq({"error" => "Missing timestamp header"})
    end

    it "with tampered body (signature doesn't match) returns 401" do
      raw = JSON.generate(valid_body)
      ts = Time.now.to_i
      sig = FaleComChannel::HmacSigner.sign(raw, "test-secret", timestamp: ts)
      tampered = JSON.generate(valid_body.merge(type: "inbound_message"))
      post "/send", tampered, "CONTENT_TYPE" => "application/json",
        "HTTP_X_FALECOM_SIGNATURE" => sig,
        "HTTP_X_FALECOM_TIMESTAMP" => ts.to_s
      expect(last_response.status).to eq(401)
      body = JSON.parse(last_response.body)
      expect(body["error"]).to match(/signature/i)
    end

    it "with stale timestamp (> 300s old) returns 401" do
      raw = JSON.generate(valid_body)
      stale_ts = Time.now.to_i - 400
      sig = FaleComChannel::HmacSigner.sign(raw, "test-secret", timestamp: stale_ts)
      post "/send", raw, "CONTENT_TYPE" => "application/json",
        "HTTP_X_FALECOM_SIGNATURE" => sig,
        "HTTP_X_FALECOM_TIMESTAMP" => stale_ts.to_s
      expect(last_response.status).to eq(401)
      body = JSON.parse(last_response.body)
      expect(body["error"]).to match(/tolerance|timestamp/i)
    end

    # ── Payload error paths ──────────────────────────────────────────────────

    it "with malformed JSON returns 422" do
      raw = "not valid json"
      ts = Time.now.to_i
      sig = FaleComChannel::HmacSigner.sign(raw, "test-secret", timestamp: ts)
      post "/send", raw, "CONTENT_TYPE" => "application/json",
        "HTTP_X_FALECOM_SIGNATURE" => sig,
        "HTTP_X_FALECOM_TIMESTAMP" => ts.to_s
      expect(last_response.status).to eq(422)
      expect(JSON.parse(last_response.body)).to eq({"error" => "Malformed JSON"})
    end

    it "with an invalid payload (fails Payload.validate!) returns 422" do
      invalid_body = {type: "outbound_message", channel: {type: "x", identifier: "y"}}
      post_signed("/send", invalid_body)
      expect(last_response.status).to eq(422)
      body = JSON.parse(last_response.body)
      expect(body).to have_key("error")
      expect(body["error"]).not_to be_empty
    end

    # ── handle_send error path ───────────────────────────────────────────────

    it "where #handle_send raises StandardError returns 500 and logs the error" do
      broken_server = Class.new(FaleComChannel::SendServer) do
        dispatch_secret "test-secret"

        def handle_send(_payload)
          raise StandardError, "downstream boom"
        end
      end

      logged_errors = []
      allow(FaleComChannel.logger).to receive(:error) { |msg| logged_errors << msg }

      mock_app = broken_server
      raw = JSON.generate(valid_body)
      ts = Time.now.to_i
      sig = FaleComChannel::HmacSigner.sign(raw, "test-secret", timestamp: ts)

      session = Rack::MockSession.new(mock_app)
      rack_response = session.request("/send",
        :method => "POST",
        :input => raw,
        "CONTENT_TYPE" => "application/json",
        "HTTP_X_FALECOM_SIGNATURE" => sig,
        "HTTP_X_FALECOM_TIMESTAMP" => ts.to_s)

      expect(rack_response.status).to eq(500)
      body = JSON.parse(rack_response.body)
      expect(body["error"]).to eq("downstream boom")
      expect(logged_errors).not_to be_empty
    end

    # ── Correlation ID ───────────────────────────────────────────────────────

    it "with X-FaleCom-Correlation-Id header propagates it to the logger during handling" do
      original_logger = FaleComChannel.logger
      io = StringIO.new
      FaleComChannel.logger = Logger.new(io).tap do |l|
        l.formatter = FaleComChannel::Logging::JsonFormatter.new
      end

      begin
        post_signed("/send", valid_body,
          extra_headers: {"HTTP_X_FALECOM_CORRELATION_ID" => "my-trace-id-123"})

        io.rewind
        log_lines = io.read.split("\n").reject(&:empty?).map { |l| JSON.parse(l) }
        expect(log_lines).not_to be_empty
        expect(log_lines.all? { |l| l["correlation_id"] == "my-trace-id-123" }).to be(true)
      ensure
        FaleComChannel.logger = original_logger
      end
    end

    it "without X-FaleCom-Correlation-Id generates a fresh uuid for the request" do
      original_logger = FaleComChannel.logger
      io = StringIO.new
      FaleComChannel.logger = Logger.new(io).tap do |l|
        l.formatter = FaleComChannel::Logging::JsonFormatter.new
      end

      begin
        post_signed("/send", valid_body)

        io.rewind
        log_lines = io.read.split("\n").reject(&:empty?).map { |l| JSON.parse(l) }
        expect(log_lines).not_to be_empty
        uuids = log_lines.map { |l| l["correlation_id"] }.compact.uniq
        expect(uuids.size).to eq(1)
        expect(uuids.first).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
      ensure
        FaleComChannel.logger = original_logger
      end
    end

    # ── Inheritance ──────────────────────────────────────────────────────────

    it "dispatch_secret and signature_tolerance are inheritable from a subclass with its own values" do
      child = Class.new(FaleComChannel::SendServer) do
        dispatch_secret "child-secret"
        signature_tolerance 60
      end

      expect(child.dispatch_secret).to eq("child-secret")
      expect(child.signature_tolerance).to eq(60)

      grandchild = Class.new(child)
      # grandchild inherits from child
      expect(grandchild.dispatch_secret).to eq("child-secret")
      expect(grandchild.signature_tolerance).to eq(60)
    end
  end
end
