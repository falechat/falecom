require "dry-struct"
require_relative "types"

module FaleComChannel
  module Payload
    class OutboundStatusUpdate < Dry::Struct
      transform_keys(&:to_sym)

      class Channel < Dry::Struct
        transform_keys(&:to_sym)

        attribute :type, Types::Strict::String
        attribute :identifier, Types::Strict::String
      end

      attribute :type, Types::Strict::String.constrained(eql: "outbound_status_update")
      attribute :channel, Channel
      attribute :external_id, Types::Strict::String
      attribute :status, Types::Strict::String.enum("sent", "delivered", "read", "failed")
      attribute :timestamp, Types::Strict::String
      attribute? :error, Types::Strict::String.optional
      attribute :metadata, Types::Strict::Hash.default({}.freeze)
    end
  end
end
