require "openssl"

module WhatsappCloud
  # Validates Meta's X-Hub-Signature-256 header against the raw request body
  # using HMAC-SHA256 with the WhatsApp app secret. Constant-time comparison
  # so attacker probing can't use timing signal.
  class SignatureVerifier
    class SignatureError < StandardError; end

    def self.verify!(raw_body, header_value, secret: ENV.fetch("WHATSAPP_APP_SECRET"))
      raise SignatureError, "missing signature header" if header_value.to_s.empty?

      provided = header_value.sub(/\Asha256=/, "")
      expected = OpenSSL::HMAC.hexdigest("SHA256", secret, raw_body)

      raise SignatureError, "signature mismatch" unless OpenSSL.secure_compare(expected, provided)

      true
    end
  end
end
