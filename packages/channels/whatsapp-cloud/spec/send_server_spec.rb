require "spec_helper"

RSpec.describe WhatsappCloud::SendServer do
  include Rack::Test::Methods

  def app
    described_class
  end

  let(:secret) { "test-dispatch-secret" }
  let(:payload) do
    {
      "type" => "outbound_message",
      "channel" => {"type" => "whatsapp_cloud", "identifier" => "15550000001"},
      "contact" => {"source_id" => "5511988888888"},
      "message" => {"internal_id" => 1, "content" => "Oi", "content_type" => "text", "attachments" => []},
      "metadata" => {"channel_credentials" => {"access_token" => "EAAG-x", "phone_number_id" => "PNID"}}
    }
  end

  before do
    ENV["FALECOM_DISPATCH_HMAC_SECRET"] = secret
    described_class.dispatch_secret(secret)
  end

  def signed_headers(body)
    ts = Time.now.to_i.to_s
    sig = FaleComChannel::HmacSigner.sign(body, secret, timestamp: ts.to_i)
    {
      "CONTENT_TYPE" => "application/json",
      "HTTP_X_FALECOM_SIGNATURE" => sig,
      "HTTP_X_FALECOM_TIMESTAMP" => ts
    }
  end

  it "delegates to Sender and returns the external_id on 200" do
    body = JSON.generate(payload)
    expect_any_instance_of(WhatsappCloud::Sender).to receive(:send_message).and_return(external_id: "wamid.abc")

    post "/send", body, signed_headers(body)

    expect(last_response.status).to eq(200)
    expect(JSON.parse(last_response.body)).to eq({"external_id" => "wamid.abc"})
  end

  it "rejects requests with an invalid HMAC signature" do
    body = JSON.generate(payload)
    post "/send", body, {
      "CONTENT_TYPE" => "application/json",
      "HTTP_X_FALECOM_SIGNATURE" => "sha256=deadbeef",
      "HTTP_X_FALECOM_TIMESTAMP" => Time.now.to_i.to_s
    }
    expect(last_response.status).to be >= 400
  end

  describe "credential resolution" do
    it "uses metadata.channel_credentials when present, ignoring ENV" do
      ENV["WHATSAPP_ACCESS_TOKEN"] = "env-tok"
      ENV["WHATSAPP_PHONE_NUMBER_ID"] = "env-pn"
      fake_sender = instance_double(WhatsappCloud::Sender, send_message: {external_id: "x"})
      expect(WhatsappCloud::Sender).to receive(:new)
        .with(access_token: "EAAG-x", phone_number_id: "PNID")
        .and_return(fake_sender)

      body = JSON.generate(payload)
      post "/send", body, signed_headers(body)
      expect(last_response.status).to eq(200)
    end

    it "falls back to ENV when channel_credentials missing" do
      ENV["WHATSAPP_ACCESS_TOKEN"] = "env-tok"
      ENV["WHATSAPP_PHONE_NUMBER_ID"] = "env-pn"
      fake_sender = instance_double(WhatsappCloud::Sender, send_message: {external_id: "x"})
      expect(WhatsappCloud::Sender).to receive(:new)
        .with(access_token: "env-tok", phone_number_id: "env-pn")
        .and_return(fake_sender)

      payload["metadata"] = {}
      body = JSON.generate(payload)
      post "/send", body, signed_headers(body)
      expect(last_response.status).to eq(200)
    end
  end

  describe "error mapping" do
    it "returns 503 on Sender::RetryableSendError" do
      expect_any_instance_of(WhatsappCloud::Sender).to receive(:send_message)
        .and_raise(WhatsappCloud::Sender::RetryableSendError.new("upstream"))

      body = JSON.generate(payload)
      post "/send", body, signed_headers(body)
      expect(last_response.status).to eq(503)
      expect(JSON.parse(last_response.body)).to eq({"error" => "upstream"})
    end

    it "returns 422 on Sender::TerminalSendError" do
      expect_any_instance_of(WhatsappCloud::Sender).to receive(:send_message)
        .and_raise(WhatsappCloud::Sender::TerminalSendError.new("invalid recipient"))

      body = JSON.generate(payload)
      post "/send", body, signed_headers(body)
      expect(last_response.status).to eq(422)
    end
  end
end
