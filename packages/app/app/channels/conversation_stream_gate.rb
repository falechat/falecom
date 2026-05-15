# Authorization PORO for Turbo Stream subscriptions. Given a connected
# user and a verified stream name, decides whether the subscription is
# allowed. Used by the Turbo::StreamsChannel monkey-patch installed in
# config/initializers/turbo_stream_gating.rb.
class ConversationStreamGate
  def self.allowed?(user, name)
    new(user, name).allowed?
  end

  def initialize(user, name)
    @user = user
    @name = name
  end

  def allowed?
    return false unless @user
    case @name
    when /\Aconversation:(\d+)\z/
      conv = Conversation.find_by(id: $1)
      conv && ConversationPolicy.new(@user, conv).can_view?
    when /\Aconversations:user:(\d+)\z/
      $1.to_i == @user.id
    when /\Aconversations:channel:(\d+)\z/
      user_channel_ids.include?($1.to_i)
    else
      false
    end
  end

  private

  def user_channel_ids
    @user_channel_ids ||= @user.teams.joins(:channel_teams).pluck("channel_teams.channel_id").uniq
  end
end
