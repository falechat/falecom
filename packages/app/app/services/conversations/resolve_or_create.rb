module Conversations
  # Returns the open Conversation for (channel, contact_channel) or creates one.
  #
  # display_id assignment is serialized with a transaction-scoped Postgres
  # advisory lock keyed on hashtext('display_id'). No `with_advisory_lock` gem
  # dependency; the lock auto-releases on commit/rollback.
  class ResolveOrCreate
    def self.call(channel, contact, contact_channel)
      ActiveRecord::Base.transaction do
        ActiveRecord::Base.connection.execute(
          "SELECT pg_advisory_xact_lock(hashtext('display_id'))"
        )

        open = channel.conversations
          .where(contact_channel: contact_channel)
          .where.not(status: "resolved")
          .order(created_at: :desc)
          .first
        return open if open

        conversation = channel.conversations.create!(
          contact: contact,
          contact_channel: contact_channel,
          status: channel.active_flow_id? ? "bot" : "queued",
          display_id: next_display_id,
          last_activity_at: Time.current
        )

        Events::Emit.call(
          name: "conversations:created",
          subject: conversation,
          actor: :system
        )

        conversation
      end
    end

    def self.next_display_id
      (Conversation.maximum(:display_id) || 0) + 1
    end

    private_class_method :next_display_id
  end
end
