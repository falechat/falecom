require "spec_helper"
require "openssl"

RSpec.describe WhatsappCloud::SignatureVerifier do
  let(:secret) { "test-app-secret" }
  let(:raw_body) { '{"object":"whatsapp_business_account","entry":[]}' }
  let(:valid_sig) { "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", secret, raw_body) }

  describe ".verify!" do
    it "returns true for a correct signature" do
      expect(described_class.verify!(raw_body, valid_sig, secret: secret)).to eq(true)
    end

    it "raises SignatureError for a mismatched signature" do
      expect {
        described_class.verify!(raw_body, "sha256=deadbeef", secret: secret)
      }.to raise_error(WhatsappCloud::SignatureVerifier::SignatureError)
    end

    it "raises SignatureError when the signature header is blank" do
      expect {
        described_class.verify!(raw_body, "", secret: secret)
      }.to raise_error(WhatsappCloud::SignatureVerifier::SignatureError)
    end

    it "uses constant-time comparison" do
      expect(OpenSSL).to receive(:secure_compare).and_call_original.at_least(:once)
      begin
        described_class.verify!(raw_body, valid_sig, secret: secret)
      rescue WhatsappCloud::SignatureVerifier::SignatureError
        # swallow — we only care that secure_compare was used
      end
    end
  end
end
