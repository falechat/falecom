module FaleComChannel
  # Base error class for all FaleComChannel errors.
  class Error < StandardError; end

  # Raised when IngestClient fails to deliver a payload to the Rails /internal/ingest endpoint.
  class IngestError < Error; end

  # Raised when DispatchClient fails to deliver an outbound message to a channel container /send endpoint.
  class DispatchError < Error; end

  module HmacSigner
    # Raised when HMAC signature verification fails — mismatched signature,
    # expired/future timestamp, or missing "sha256=" prefix.
    class InvalidSignatureError < FaleComChannel::Error; end
  end
end
