class ConversationListRowComponent < ViewComponent::Base
  def initialize(conversation:, active: false, unread: false)
    @conversation = conversation
    @active = active
    @unread = unread
  end

  def preview
    @conversation.messages.order(created_at: :desc).first&.content.to_s.truncate(60)
  end

  def time_ago
    return "—" unless @conversation.last_activity_at
    helpers.time_ago_in_words(@conversation.last_activity_at) + " ago"
  end

  def status
    @conversation.status
  end

  def status_dot_class
    {"bot" => "bg-blue-500", "queued" => "bg-yellow-500", "assigned" => "bg-green-500", "resolved" => "bg-gray-400"}[status]
  end
end
