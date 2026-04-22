module Messages
  # Single entry point for every Message creation. Kwargs-based so inbound,
  # outbound, bot, and system callers share one API.
  #
  # Returns a Message decorated with a #duplicate? method:
  #   - false if this call inserted the row
  #   - true  if an existing row with the same (channel_id, external_id)
  #           was found (via ON CONFLICT); caller should skip broadcast
  #           + event emission.
  class Create
    def self.call(conversation:, direction:, content:, content_type:, status:,
      sender: nil, external_id: nil, reply_to_external_id: nil, sent_at: nil,
      metadata: {}, raw: nil)
      attrs = {
        channel_id: conversation.channel_id,
        conversation_id: conversation.id,
        direction: direction,
        content: content,
        content_type: content_type,
        status: status,
        sender_type: sender&.class&.base_class&.name,
        sender_id: sender&.id,
        external_id: external_id,
        reply_to_external_id: reply_to_external_id,
        sent_at: sent_at,
        metadata: metadata.to_h,
        raw: raw
      }

      message = if external_id.present?
        insert_with_conflict(attrs, conversation: conversation, external_id: external_id)
      else
        attach_duplicate_flag(Message.create!(attrs), false)
      end

      return message if message.duplicate?

      conversation.update!(last_activity_at: Time.current)
      emit_event(message, direction, sender)
      message
    end

    def self.insert_with_conflict(attrs, conversation:, external_id:)
      now = Time.current
      result = Message.insert_all(
        [attrs.merge(created_at: now, updated_at: now)],
        returning: [:id],
        unique_by: :index_messages_on_channel_id_and_external_id
      )

      if result.rows.empty?
        existing = Message.find_by!(
          channel_id: conversation.channel_id,
          external_id: external_id
        )
        attach_duplicate_flag(existing, true)
      else
        attach_duplicate_flag(Message.find(result.rows.first.first), false)
      end
    end

    def self.attach_duplicate_flag(message, value)
      message.define_singleton_method(:duplicate?) { value }
      message
    end

    def self.emit_event(message, direction, sender)
      name = (direction == "inbound") ? "messages:inbound" : "messages:outbound"
      Events::Emit.call(name: name, subject: message, actor: sender || :system)
    end

    private_class_method :insert_with_conflict, :attach_duplicate_flag, :emit_event
  end
end
