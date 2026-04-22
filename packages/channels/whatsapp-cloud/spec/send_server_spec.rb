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
end
