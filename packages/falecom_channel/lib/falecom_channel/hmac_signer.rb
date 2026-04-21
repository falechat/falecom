require "openssl"

module FaleComChannel
  module HmacSigner
    SIGNATURE_PREFIX = "sha256="
    DEFAULT_TOLERANCE = 300

    module_function

    # Signs a request body with HMAC-SHA256.
    #
    # @param body [String] the raw request body
    # @param secret [String] the shared HMAC secret
    # @param timestamp [Integer] unix seconds — included in the signed payload
    # @return [String] "sha256=<64-char hex digest>"
    def sign(body, secret, timestamp:)
      payload = "#{timestamp}.#{body}"
      hex = OpenSSL::HMAC.hexdigest("SHA256", secret, payload)
      "#{SIGNATURE_PREFIX}#{hex}"
    end

    # Verifies a request signature.
    #
    # @param body [String] the raw request body
    # @param signature [String] the X-FaleCom-Signature header value
    # @param timestamp [Integer] the X-FaleCom-Timestamp header value
    # @param secret [String] the shared HMAC secret
    # @param tolerance [Integer] max allowed age (and future skew) in seconds (default 300)
    # @return [true] on success
    # @raise [FaleComChannel::HmacSigner::InvalidSignatureError] on any failure
    def verify!(body, signature, timestamp, secret, tolerance: DEFAULT_TOLERANCE)
      unless signature.start_with?(SIGNATURE_PREFIX)
        raise InvalidSignatureError, "Signature is missing the sha256= prefix"
      end

      skew = (Time.now.to_i - timestamp).abs
      if skew > tolerance
        raise InvalidSignatureError, "Timestamp is outside the allowed tolerance (skew=#{skew}s, tolerance=#{tolerance}s)"
      end

      expected = sign(body, secret, timestamp: timestamp)

      unless OpenSSL.secure_compare(expected, signature)
        raise InvalidSignatureError, "Signature mismatch"
      end

      true
    end
  end
end
