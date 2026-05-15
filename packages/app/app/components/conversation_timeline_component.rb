class ConversationTimelineComponent < ViewComponent::Base
  EVENT_WHITELIST = %w[
    conversations:assigned
    conversations:transferred
    conversations:resolved
    flows:handoff
    users:availability_changed
  ].freeze

  def initialize(conversation:)
    @conversation = conversation
  end

  def items
    messages = @conversation.messages.to_a
    events = Event.where(subject: @conversation, name: EVENT_WHITELIST).to_a
    (messages + events).sort_by { |i| [i.created_at, i.is_a?(Message) ? 0 : 1, i.id] }
  end
end
