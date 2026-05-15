module Conversations
  # Central place that knows where to broadcast every conversation/message
  # state change. Stream targets:
  #
  #   conversation:<conv_id>            — per-conversation timeline (active viewers)
  #   conversations:channel:<channel_id>— row updates for the channel feed
  #   conversations:user:<user_id>      — per-agent "Mine" list
  #
  # All methods swallow broadcast errors (logged) so a failing cable backend
  # never rolls back the underlying state change.
  module Broadcasts
    module_function

    def message_appended(message)
      conv = message.conversation
      safely do
        Turbo::StreamsChannel.broadcast_append_to(
          "conversation:#{conv.id}",
          target: "messages",
          partial: "dashboard/conversations/timeline_message",
          locals: {message: message}
        )
      end
      broadcast_row(conv)
    end

    def message_status_changed(message)
      conv = message.conversation
      safely do
        Turbo::StreamsChannel.broadcast_replace_to(
          "conversation:#{conv.id}",
          target: ActionView::RecordIdentifier.dom_id(message),
          partial: "dashboard/conversations/timeline_message",
          locals: {message: message}
        )
      end
      broadcast_row(conv)
    end

    def assigned(conversation)
      broadcast_row(conversation)
      return unless conversation.assignee_id
      safely do
        Turbo::StreamsChannel.broadcast_prepend_to(
          "conversations:user:#{conversation.assignee_id}",
          target: "mine-list",
          partial: "dashboard/conversations/list_row",
          locals: {conversation: conversation}
        )
      end
    end

    def transferred(conversation, from_user_id:, from_team_id:)
      if from_user_id
        safely do
          Turbo::StreamsChannel.broadcast_remove_to(
            "conversations:user:#{from_user_id}",
            target: ActionView::RecordIdentifier.dom_id(conversation)
          )
        end
      end
      assigned(conversation)
    end

    def resolved(conversation)
      broadcast_row(conversation)
      return unless conversation.assignee_id
      safely do
        Turbo::StreamsChannel.broadcast_remove_to(
          "conversations:user:#{conversation.assignee_id}",
          target: ActionView::RecordIdentifier.dom_id(conversation)
        )
      end
    end

    def broadcast_row(conversation)
      safely do
        Turbo::StreamsChannel.broadcast_replace_to(
          "conversations:channel:#{conversation.channel_id}",
          target: ActionView::RecordIdentifier.dom_id(conversation),
          partial: "dashboard/conversations/list_row",
          locals: {conversation: conversation}
        )
      end
    end

    def safely
      yield
    rescue => e
      Rails.logger.warn(event: "broadcast_failed", error: e.message)
    end
  end
end
