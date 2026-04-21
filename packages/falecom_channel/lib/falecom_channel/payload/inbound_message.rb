require "dry-struct"
require_relative "types"

module FaleComChannel
  module Payload
    class InboundMessage < Dry::Struct
      transform_keys(&:to_sym)

      class Channel < Dry::Struct
        transform_keys(&:to_sym)

        attribute :type, Types::Strict::String
        attribute :identifier, Types::Strict::String
      end

      class Contact < Dry::Struct
        transform_keys(&:to_sym)

        attribute :source_id, Types::Strict::String
        attribute? :name, Types::Strict::String.optional
        attribute? :phone_number, Types::Strict::String.optional
        attribute? :email, Types::Strict::String.optional
        attribute? :avatar_url, Types::Strict::String.optional
      end

      class Message < Dry::Struct
        transform_keys(&:to_sym)

        attribute :external_id, Types::Strict::String
        attribute :direction, Types::Strict::String.enum("inbound", "outbound")
        attribute? :content, Types::Strict::String.optional
        attribute :content_type, Types::Strict::String.enum(*Types::CONTENT_TYPES)
        attribute :attachments, Types::Strict::Array.default([].freeze)
        attribute :sent_at, Types::Strict::String
        attribute? :reply_to_external_id, Types::Strict::String.optional
      end

      attribute :type, Types::Strict::String.constrained(eql: "inbound_message")
      attribute :channel, Channel
      attribute :contact, Contact
      attribute :message, Message
      attribute :metadata, Types::Strict::Hash.default({}.freeze)
      attribute? :raw, Types::Strict::Hash.optional
    end
  end
end
