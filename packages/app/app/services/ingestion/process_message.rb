module Ingestion
  # Orchestrates the inbound message flow inside a single DB transaction.
  # Delegates to Contacts::Resolve, Conversations::ResolveOrCreate, and
  # Messages::Create. Short-circuits on duplicate external_id (no broadcast,
  # no second event). Flow advance + auto-assign are deferred to later specs.
  class ProcessMessage
    def self.call(channel, payload)
      ActiveRecord::Base.transaction do
        contact, contact_channel = Contacts::Resolve.call(channel, payload.fetch("contact"))
        conversation, conversation_created = Conversations::ResolveOrCreate.call(channel, contact, contact_channel)

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

        if conversation_created && conversation.status == "queued"
          ActiveRecord::Base.connection.current_transaction.after_commit do
            AutoAssignJob.perform_later(conversation.id)
          end
        end

        broadcast(conversation, message)
        message
      end
    end

    def self.broadcast(_conversation, message)
      Conversations::Broadcasts.message_appended(message)
    end

    private_class_method :broadcast
  end
end
