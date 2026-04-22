require "json"

module WhatsappCloud
  # Meta WhatsApp Cloud webhook → Common Ingestion Payload.
  # Plan 04b scope: text inbound + status updates only.
  class Parser
    class UnsupportedContentTypeError < StandardError; end

    def self.to_common_payload(raw_body)
      json = raw_body.is_a?(String) ? JSON.parse(raw_body) : raw_body
      value = json.dig("entry", 0, "changes", 0, "value") || {}

      if value["statuses"]
        parse_status(value)
      elsif value["messages"]
        parse_inbound(value, raw: json)
      else
        raise UnsupportedContentTypeError, "unknown payload shape"
      end
    end

    def self.parse_inbound(value, raw:)
      message = value.fetch("messages").first
      type = message["type"]

      raise UnsupportedContentTypeError, "unsupported content_type: #{type}" unless type == "text"

      contact = (value["contacts"] || []).first || {}
      metadata = value["metadata"] || {}

      {
        "type" => "inbound_message",
        "channel" => {
          "type" => "whatsapp_cloud",
          "identifier" => metadata.fetch("display_phone_number", metadata["phone_number_id"])
        },
        "contact" => {
          "source_id" => message.fetch("from"),
          "name" => contact.dig("profile", "name"),
          "phone_number" => "+#{message.fetch("from")}"
        },
        "message" => {
          "external_id" => message.fetch("id"),
          "direction" => "inbound",
          "content" => message.dig("text", "body"),
          "content_type" => "text",
          "attachments" => [],
          "sent_at" => Time.at(message.fetch("timestamp").to_i).utc.iso8601,
          "reply_to_external_id" => message.dig("context", "id")
        },
        "metadata" => {
          "whatsapp_context" => {
            "business_account_id" => metadata["business_account_id"],
            "phone_number_id" => metadata["phone_number_id"]
          }
        },
        "raw" => raw
      }
    end

    def self.parse_status(value)
      status = value.fetch("statuses").first
      metadata = value["metadata"] || {}
      {
        "type" => "outbound_status_update",
        "channel" => {
          "type" => "whatsapp_cloud",
          "identifier" => metadata.fetch("display_phone_number", metadata["phone_number_id"])
        },
        "external_id" => status.fetch("id"),
        "status" => status.fetch("status"),
        "timestamp" => Time.at(status.fetch("timestamp").to_i).utc.iso8601,
        "error" => status.dig("errors", 0, "message"),
        "metadata" => {"recipient_id" => status["recipient_id"]}
      }
    end

    private_class_method :parse_inbound, :parse_status
  end
end
