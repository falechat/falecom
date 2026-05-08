require "faraday"
require "json"

module WhatsappCloud
  # Translates the Common outbound payload into a Meta Graph API v21.0 /messages call.
  # Text-only.
  class Sender
    class SendError < StandardError; end
    class RetryableSendError < SendError; end
    class TerminalSendError < SendError; end

    DEFAULT_BASE_URL = "https://graph.facebook.com".freeze

    def initialize(access_token:, phone_number_id:, connection: nil)
      @access_token = access_token
      @phone_number_id = phone_number_id
      @conn = connection || default_connection
    end

    def send_message(payload)
      message = payload.fetch("message")
      content_type = message.fetch("content_type")
      raise TerminalSendError, "content_type: #{content_type} not supported" unless content_type == "text"

      response = @conn.post("/v21.0/#{@phone_number_id}/messages") do |req|
        req.headers["Authorization"] = "Bearer #{@access_token}"
        req.body = build_body(payload, message)
      end

      handle_response(response)
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      raise RetryableSendError, e.message
    end

    private

    def build_body(payload, message)
      {
        messaging_product: "whatsapp",
        to: payload.dig("contact", "source_id"),
        type: "text",
        text: {body: message.fetch("content")}
      }
    end

    def handle_response(response)
      parsed = parse_body(response.body)
      status = response.status

      if (200..299).cover?(status)
        id = parsed.dig("messages", 0, "id")
        raise TerminalSendError, "missing message id in response" unless id
        {external_id: id}
      elsif (500..599).cover?(status)
        raise RetryableSendError, parsed.dig("error", "message") || "send failed (#{status})"
      else
        raise TerminalSendError, parsed.dig("error", "message") || "send failed (#{status})"
      end
    end

    def parse_body(body)
      return body if body.is_a?(Hash)
      JSON.parse(body.to_s)
    rescue JSON::ParserError
      {}
    end

    def default_connection
      Faraday.new(url: ENV.fetch("META_API_BASE", DEFAULT_BASE_URL)) do |f|
        f.request :json
        f.adapter Faraday.default_adapter
        f.options.timeout = 10
        f.options.open_timeout = 5
      end
    end
  end
end
