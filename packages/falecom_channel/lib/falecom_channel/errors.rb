module FaleComChannel
  # Base error class for all FaleComChannel errors.
  class Error < StandardError; end

  module HmacSigner
    # Raised when HMAC signature verification fails — mismatched signature,
    # expired/future timestamp, or missing "sha256=" prefix.
    class InvalidSignatureError < FaleComChannel::Error; end
  end
end
