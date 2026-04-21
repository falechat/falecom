require_relative "errors"
require_relative "payload/types"
require_relative "payload/inbound_message"
require_relative "payload/outbound_status_update"
require_relative "payload/outbound_message"

module FaleComChannel
  class InvalidPayloadError < Error; end

  module Payload
    SCHEMA_MAP = {
      "inbound_message" => InboundMessage,
      "outbound_status_update" => OutboundStatusUpdate,
      "outbound_message" => OutboundMessage
    }.freeze

    module_function

    def validate!(hash)
      type = hash[:type] || hash["type"]

      raise InvalidPayloadError, "Payload is missing required field: type" if type.nil?

      schema_class = SCHEMA_MAP[type]
      raise InvalidPayloadError, "Unknown payload type: #{type.inspect}" unless schema_class

      begin
        schema_class.new(hash)
      rescue Dry::Struct::Error => e
        raise InvalidPayloadError, e.message
      end
    end

    def valid?(hash)
      validate!(hash)
      true
    rescue InvalidPayloadError
      false
    end

    def parse(hash)
      validate!(hash)
    end
  end
end
