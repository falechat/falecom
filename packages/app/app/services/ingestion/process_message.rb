module Ingestion
  # Orchestrates the inbound message flow inside a single DB transaction.
  # Delegates to Contacts::Resolve, Conversations::ResolveOrCreate, and
  # Messages::Create. Short-circuits on duplicate external_id (no broadcast,
  # no second event). Flow advance + auto-assign are deferred to later specs.
  class ProcessMessage
    def self.call(channel, payload)
      ActiveRecord::Base.transaction do
        contact, contact_channel = Contacts::Resolve.call(channel, payload.fetch("contact"))
        conversation = Conversations::ResolveOrCreate.call(channel, contact, contact_channel)

        message_data = payload.fetch("message")
        message = Messages::Create.call(
          conversation: conversation,
          direction: "inbound",
          content: message_data["content"],
          content_type: message_data.fetch("content_type"),
          status: "received",
          sender: contact,
          external_id: message_data["external_id"],
          reply_to_external_id: message_data["reply_to_external_id"],
          sent_at: message_data["sent_at"],
          metadata: payload["metadata"].to_h,
          raw: payload["raw"]
        )

        return message if message.duplicate?

        broadcast(conversation, message)
        message
      end
    end

    def self.broadcast(conversation, message)
      Turbo::StreamsChannel.broadcast_append_to(
        "conversation:#{conversation.id}",
        target: "messages",
        partial: "dashboard/messages/message",
        locals: {message: message}
      )
    rescue => e
      # Broadcast failure must not roll back ingestion. Log only.
      Rails.logger.warn(
        event: "ingestion_broadcast_failed",
        conversation_id: conversation.id,
        message_id: message.id,
        error: e.message
      )
    end

    private_class_method :broadcast
  end
end
