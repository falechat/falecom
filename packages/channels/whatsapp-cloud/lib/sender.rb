require "faraday"
require "json"

module WhatsappCloud
  # Translates the Common outbound payload into a Meta Graph API v21.0 /messages call.
  # Text-only for Plan 04b.
  class Sender
    class SendError < StandardError; end

    BASE_URL = "https://graph.facebook.com"

    def initialize(access_token:, phone_number_id:, connection: nil)
      @access_token = access_token
      @phone_number_id = phone_number_id
      @conn = connection || Faraday.new(url: BASE_URL) do |f|
        f.request :json
        f.adapter Faraday.default_adapter
        f.options.timeout = 10
        f.options.open_timeout = 5
      end
    end

    def send_message(payload)
      message = payload.fetch("message")
      content_type = message.fetch("content_type")
      raise NotImplementedError, "content_type: #{content_type} not supported" unless content_type == "text"

      body = {
        messaging_product: "whatsapp",
        to: payload.dig("contact", "source_id"),
        type: "text",
        text: {body: message.fetch("content")}
      }

      response = @conn.post("/v21.0/#{@phone_number_id}/messages") do |req|
        req.headers["Authorization"] = "Bearer #{@access_token}"
        req.body = body
      end

      if (200..299).cover?(response.status)
        parsed = response.body.is_a?(String) ? JSON.parse(response.body) : response.body
        {external_id: parsed.dig("messages", 0, "id")}
      else
        parsed = begin
          response.body.is_a?(String) ? JSON.parse(response.body) : response.body
        rescue JSON::ParserError
          {}
        end
        raise SendError, parsed.dig("error", "message") || "send failed (#{response.status})"
      end
    end
  end
end
