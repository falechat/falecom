require "spec_helper"
require "openssl"

HMAC_TEST_SECRET = "test-secret"
HMAC_TEST_TIMESTAMP = Time.now.to_i

RSpec.describe FaleComChannel::HmacSigner do
  let(:body) { '{"event":"message_ingested"}' }
  let(:secret) { HMAC_TEST_SECRET }
  let(:timestamp) { HMAC_TEST_TIMESTAMP }
  let(:signature) { described_class.sign(body, secret, timestamp: timestamp) }

  describe ".sign" do
    it ".sign returns \"sha256=<hex>\" where the hex matches OpenSSL::HMAC.hexdigest(\"<timestamp>.<body>\", SECRET)" do
      expected_hex = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{body}")
      expect(signature).to eq("sha256=#{expected_hex}")
    end

    it ".sign produces a 64-character hex digest (SHA-256)" do
      hex_part = signature.delete_prefix("sha256=")
      expect(hex_part.length).to eq(64)
    end

    it ".sign is stable — same body, secret, timestamp produce the same signature" do
      sig1 = described_class.sign(body, secret, timestamp: timestamp)
      sig2 = described_class.sign(body, secret, timestamp: timestamp)
      expect(sig1).to eq(sig2)
    end
  end

  describe ".verify!" do
    it ".verify! returns true for a valid signature within tolerance" do
      expect(described_class.verify!(body, signature, timestamp, secret)).to be true
    end

    it ".verify! raises InvalidSignatureError when the body is tampered" do
      tampered_body = body + "tampered"
      expect {
        described_class.verify!(tampered_body, signature, timestamp, secret)
      }.to raise_error(FaleComChannel::HmacSigner::InvalidSignatureError)
    end

    it ".verify! raises InvalidSignatureError when the signature is tampered" do
      tampered_signature = "sha256=" + ("a" * 64)
      expect {
        described_class.verify!(body, tampered_signature, timestamp, secret)
      }.to raise_error(FaleComChannel::HmacSigner::InvalidSignatureError)
    end

    it ".verify! raises InvalidSignatureError when the signature is missing the \"sha256=\" prefix" do
      no_prefix_signature = signature.delete_prefix("sha256=")
      expect {
        described_class.verify!(body, no_prefix_signature, timestamp, secret)
      }.to raise_error(FaleComChannel::HmacSigner::InvalidSignatureError)
    end

    it ".verify! raises InvalidSignatureError when timestamp is older than tolerance" do
      old_timestamp = Time.now.to_i - 400
      old_signature = described_class.sign(body, secret, timestamp: old_timestamp)
      expect {
        described_class.verify!(body, old_signature, old_timestamp, secret)
      }.to raise_error(FaleComChannel::HmacSigner::InvalidSignatureError)
    end

    it ".verify! raises InvalidSignatureError when timestamp is more than tolerance in the future (clock skew)" do
      future_timestamp = Time.now.to_i + 400
      future_signature = described_class.sign(body, secret, timestamp: future_timestamp)
      expect {
        described_class.verify!(body, future_signature, future_timestamp, secret)
      }.to raise_error(FaleComChannel::HmacSigner::InvalidSignatureError)
    end

    it ".verify! uses OpenSSL.secure_compare (constant-time)" do
      expected_sig = described_class.sign(body, secret, timestamp: timestamp)
      expect(OpenSSL).to receive(:secure_compare).with(expected_sig, signature).and_call_original
      described_class.verify!(body, signature, timestamp, secret)
    end

    it ".verify! accepts a custom tolerance override" do
      old_timestamp = Time.now.to_i - 400
      old_signature = described_class.sign(body, secret, timestamp: old_timestamp)
      expect(described_class.verify!(body, old_signature, old_timestamp, secret, tolerance: 600)).to be true
    end
  end

  describe "InvalidSignatureError" do
    it "InvalidSignatureError is a subclass of FaleComChannel::Error" do
      expect(FaleComChannel::HmacSigner::InvalidSignatureError.ancestors).to include(FaleComChannel::Error)
    end
  end
end
