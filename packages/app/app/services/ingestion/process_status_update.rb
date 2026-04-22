module Ingestion
  # Applies a provider status update (`sent → delivered → read`, or `failed`
  # at any point) to the matching outbound Message. Returns:
  #   :updated — status moved forward (or failed set)
  #   :noop    — already-current status or a backward-moving update
  #   :retry   — no message found; caller should return 422 so the
  #              channel container NACKs and SQS redelivers after the
  #              visibility timeout.
  class ProcessStatusUpdate
    LIFECYCLE = %w[pending sent delivered read].freeze

    def self.call(channel, payload)
      external_id = payload.fetch("external_id")
      message = channel.messages.find_by(external_id: external_id)
      return :retry unless message

      new_status = payload.fetch("status")
      return :noop unless progression_allowed?(message.status, new_status)

      attrs = {status: new_status}
      attrs[:error] = payload["error"] if payload["error"].present?
      message.update!(attrs)

      Events::Emit.call(name: "messages:#{new_status}", subject: message, actor: :system)

      broadcast(message)
      :updated
    end

    def self.progression_allowed?(current, incoming)
      return false if current == incoming
      return true if incoming == "failed"
      LIFECYCLE.index(incoming).to_i > LIFECYCLE.index(current).to_i
    end

    def self.broadcast(message)
      Turbo::StreamsChannel.broadcast_replace_to(
        "conversation:#{message.conversation_id}",
        target: "message_#{message.id}_status",
        partial: "dashboard/messages/status",
        locals: {message: message}
      )
    rescue => e
      Rails.logger.warn(
        event: "status_update_broadcast_failed",
        message_id: message.id,
        error: e.message
      )
    end

    private_class_method :progression_allowed?, :broadcast
  end
end
