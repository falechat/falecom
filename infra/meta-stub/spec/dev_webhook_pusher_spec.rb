require "spec_helper"

RSpec.describe MetaStub::DevWebhookPusher do
  it "POSTs the body to dev-webhook with a valid X-Hub-Signature-256" do
    payload = {object: "whatsapp_business_account"}
    expected_body = JSON.generate(payload)
    expected_sig = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", "test-app-secret", expected_body)

    stub_request(:post, "http://dev-webhook:4000/webhooks/whatsapp-cloud")
      .with(
        body: expected_body,
        headers: {"X-Hub-Signature-256" => expected_sig, "Content-Type" => "application/json"}
      )
      .to_return(status: 200, body: '{"status":"enqueued"}')

    res = described_class.new.push(payload)
    expect(res.code).to eq("200")
  end
end
