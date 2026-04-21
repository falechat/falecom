require "faraday"
require "json"
require "securerandom"
require "time"

module FaleComChannel
  # HTTP client for sending outbound messages to a channel container's /send endpoint.
  #
  # Used by Rails (Spec 05) when dispatching messages to a channel container.
  # No retries — Solid Queue handles retry semantics at the job level.
  #
  # Example:
  #   client = FaleComChannel::DispatchClient.new(
  #     container_url: ENV.fetch("CHANNEL_WHATSAPP_CLOUD_URL"),
  #     secret:        ENV.fetch("FALECOM_DISPATCH_HMAC_SECRET")
  #   )
  #   result = client.send_message(payload_hash)
  #   # => { "external_id" => "wamid.abc123" }
  class DispatchClient
    # @param container_url [String] base URL of the channel container (e.g. "http://whatsapp-cloud:3001")
    # @param secret [String] HMAC secret for signing (FALECOM_DISPATCH_HMAC_SECRET)
    # @param connection [Faraday::Connection, nil] optional Faraday connection for test injection
    def initialize(container_url:, secret:, connection: nil)
      @container_url = container_url
      @secret = secret
      @connection = connection || build_connection
    end

    # Posts a message payload to the channel container's /send endpoint.
    #
    # @param payload_hash [Hash] the outbound message payload
    # @return [Hash] parsed JSON response body (empty Hash if body is blank)
    # @raise [FaleComChannel::DispatchError] on any non-2xx response
    def send_message(payload_hash)
      body = JSON.generate(payload_hash)
      ts = Time.now.to_i
      signature = HmacSigner.sign(body, @secret, timestamp: ts)
      correlation_id = Logging.current_correlation_id || SecureRandom.uuid

      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      begin
        response = @connection.post("/send") do |req|
          req.headers["Content-Type"] = "application/json"
          req.headers["X-FaleCom-Signature"] = signature
          req.headers["X-FaleCom-Timestamp"] = ts.to_s
          req.headers["X-FaleCom-Correlation-Id"] = correlation_id
          req.body = body
        end

        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round

        FaleComChannel.logger.info(
          event: "dispatch_post",
          status: response.status,
          duration_ms: duration_ms
        )

        parse_body(response.body)
      rescue Faraday::Error => e
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
        status = e.response ? e.response[:status] : nil
        resp_body = e.response ? e.response[:body] : nil

        FaleComChannel.logger.error(
          event: "dispatch_post_failed",
          status: status,
          duration_ms: duration_ms,
          error: e.message
        )

        raise DispatchError, "Dispatch failed — status=#{status} body=#{resp_body}"
      end
    end

    private

    def build_connection
      Faraday.new(url: @container_url) do |f|
        f.response :raise_error
        f.adapter Faraday.default_adapter
        f.options.timeout = 30
        f.options.open_timeout = 5
      end
    end

    def parse_body(body)
      return {} if body.nil? || body.strip.empty?

      JSON.parse(body)
    rescue JSON::ParserError
      {}
    end
  end
end
