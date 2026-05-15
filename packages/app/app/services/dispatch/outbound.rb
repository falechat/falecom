module Dispatch
  class Outbound
    def self.call(conversation:, content:, actor:, content_type: "text", attachments: [], metadata: {}, reply_to_external_id: nil)
      sender = actor.is_a?(Symbol) ? nil : actor
      message = Messages::Create.call(
        conversation: conversation,
        direction: "outbound",
        content: content,
        content_type: content_type,
        status: "pending",
        sender: sender,
        metadata: metadata,
        reply_to_external_id: reply_to_external_id
      )

      # Solid Queue is DB-backed: the SendMessageJob INSERT rides the same
      # transaction as the Message INSERT, so workers can't pick up the job
      # before the message row is visible. No after-commit deferral needed.
      SendMessageJob.perform_later(message.id)

      message
    end
  end
end
