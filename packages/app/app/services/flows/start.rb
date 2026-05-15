module Flows
  class Start
    def self.call(conversation)
      channel = conversation.channel
      flow = channel.active_flow
      return unless flow&.is_active?

      greeting_node = pick_greeting_node(conversation, flow)

      ConversationFlow.create!(
        conversation: conversation,
        flow: flow,
        current_node: greeting_node,
        status: "active",
        started_at: Time.current
      )

      Events::Emit.call(name: "flows:started", subject: conversation, actor: :bot)
      Flows::Advance.call(conversation, nil)
    end

    def self.pick_greeting_node(conversation, flow)
      return flow.root_node if flow.short_greeting_node.nil?

      last_at = Conversation
        .where(contact_channel_id: conversation.contact_channel_id)
        .where.not(id: conversation.id)
        .joins(:messages)
        .maximum("messages.created_at")

      if last_at && (Time.current - last_at) < flow.inactivity_threshold_hours.hours
        flow.short_greeting_node
      else
        flow.root_node
      end
    end
  end
end
