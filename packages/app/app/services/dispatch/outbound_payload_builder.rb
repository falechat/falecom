module Dispatch
  class OutboundPayloadBuilder
    def self.call(message)
      channel = message.channel
      conversation = message.conversation
      contact_channel = conversation.contact_channel

      {
        type: "outbound_message",
        channel: {
          type: channel.channel_type,
          identifier: channel.identifier
        },
        contact: {
          source_id: contact_channel.source_id
        },
        message: {
          internal_id: message.id,
          content: message.content,
          content_type: message.content_type,
          attachments: [],
          reply_to_external_id: message.reply_to_external_id
        },
        metadata: message.metadata.to_h.merge(
          "channel_credentials" => channel.credentials.to_h.deep_stringify_keys
        )
      }
    end
  end
end
