require "faraday"
require "faraday/retry"
require "json"
require "securerandom"
require "time"

module FaleComChannel
  # HTTP client for posting inbound payloads to the Rails /internal/ingest endpoint.
  #
  # Used by channel containers after pulling a message from SQS and validating it.
  # Retries on 5xx (up to 3 retries with exponential backoff). Does NOT retry on 4xx —
  # those indicate validation failures.
  #
  # Example:
  #   client = FaleComChannel::IngestClient.new(
  #     api_url: ENV.fetch("FALECOM_API_URL"),
  #     secret:  ENV.fetch("FALECOM_INGEST_HMAC_SECRET")
  #   )
  #   result = client.post(payload_hash)
  #   # => { "message_id" => 123 }
  class IngestClient
    # @param api_url [String] base URL of the Rails app (e.g. "http://rails:3000")
    # @param secret [String] HMAC secret for signing (FALECOM_INGEST_HMAC_SECRET)
    # @param connection [Faraday::Connection, nil] optional Faraday connection for test injection
    def initialize(api_url:, secret:, connection: nil)
      @api_url = api_url
      @secret = secret
      @connection = connection || build_connection
    end

    # Posts a payload to the Rails /internal/ingest endpoint.
    #
    # @param payload_hash [Hash] the ingestion payload
    # @return [Hash] parsed JSON response body (empty Hash if body is blank)
    # @raise [FaleComChannel::IngestError] on persistent failure or immediate 4xx
    def post(payload_hash)
      body = JSON.generate(payload_hash)
      ts = Time.now.to_i
      signature = HmacSigner.sign(body, @secret, timestamp: ts)
      correlation_id = Logging.current_correlation_id || SecureRandom.uuid

      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      begin
        response = @connection.post("/internal/ingest") do |req|
          req.headers["Content-Type"] = "application/json"
          req.headers["X-FaleCom-Signature"] = signature
          req.headers["X-FaleCom-Timestamp"] = ts.to_s
          req.headers["X-FaleCom-Correlation-Id"] = correlation_id
          req.body = body
        end

        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round

        FaleComChannel.logger.info(
          event: "ingest_post",
          status: response.status,
          duration_ms: duration_ms
        )

        parse_body(response.body)
      rescue Faraday::Error => e
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
        status = e.response ? e.response[:status] : nil
        resp_body = e.response ? e.response[:body] : nil

        FaleComChannel.logger.error(
          event: "ingest_post_failed",
          status: status,
          duration_ms: duration_ms,
          error: e.message
        )

        raise IngestError, "Ingest failed — status=#{status} body=#{resp_body}"
      end
    end

    private

    def build_connection
      # raise_error must be declared before retry so that retry is the outermost
      # wrapper in the Faraday stack. On the response path: adapter → raise_error
      # → retry, allowing the retry middleware to catch raised errors and re-attempt.
      Faraday.new(url: @api_url) do |f|
        f.response :raise_error
        f.request :retry, max: 3, interval: 0.5, backoff_factor: 2,
          retry_statuses: [500, 502, 503, 504], methods: %i[post get]
        f.adapter Faraday.default_adapter
        f.options.timeout = 10
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
