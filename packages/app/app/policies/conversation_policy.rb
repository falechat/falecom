class ConversationPolicy
  attr_reader :user, :conversation

  def initialize(user, conversation)
    @user = user
    @conversation = conversation
  end

  def can_view?
    return true if user.admin?
    user_channel_ids.include?(conversation.channel_id)
  end

  def can_reply?
    can_view? && conversation.assignee_id == user.id
  end

  def can_pickup?
    can_view? && conversation.assignee_id.nil? && conversation.status == "queued"
  end

  def can_transfer?
    return true if user.admin?
    return true if user.supervisor? && can_view?
    return true if can_pickup?
    conversation.assignee_id == user.id && can_view?
  end

  def can_resolve?
    return true if user.admin?
    return true if user.supervisor? && can_view?
    can_reply?
  end

  private

  def user_channel_ids
    @user_channel_ids ||= user.teams
      .joins(:channel_teams)
      .pluck("channel_teams.channel_id")
      .uniq
  end
end
