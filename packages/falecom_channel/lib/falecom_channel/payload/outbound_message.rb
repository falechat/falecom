require "dry-struct"
require_relative "types"

module FaleComChannel
  module Payload
    class OutboundMessage < Dry::Struct
      transform_keys(&:to_sym)

      class Channel < Dry::Struct
        transform_keys(&:to_sym)

        attribute :type, Types::Strict::String
        attribute :identifier, Types::Strict::String
      end

      class Contact < Dry::Struct
        transform_keys(&:to_sym)

        attribute :source_id, Types::Strict::String
      end

      class Message < Dry::Struct
        transform_keys(&:to_sym)

        attribute :internal_id, Types::Strict::Integer
        attribute? :content, Types::Strict::String.optional
        attribute :content_type, Types::Strict::String
        attribute :attachments, Types::Strict::Array.default([].freeze)
        attribute? :reply_to_external_id, Types::Strict::String.optional
      end

      attribute :type, Types::Strict::String.constrained(eql: "outbound_message")
      attribute :channel, Channel
      attribute :contact, Contact
      attribute :message, Message
      attribute :metadata, Types::Strict::Hash.default({}.freeze)
    end
  end
end
