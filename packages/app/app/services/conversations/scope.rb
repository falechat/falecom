module Conversations
  class Scope
    def self.call(user:, params:) = new(user: user, params: params).call

    def initialize(user:, params:)
      @user = user
      @params = params
    end

    def call
      base = view_scope.merge(access_scope)
      base.order(Arel.sql("last_activity_at DESC NULLS LAST, created_at DESC"))
        .includes(:channel, :contact, :assignee, :team)
    end

    private

    def view_scope
      case @params[:view].to_s
      when "unassigned" then ::Conversation.where(assignee_id: nil, status: "queued")
      when "team"       then ::Conversation.where(team_id: user_team_ids)
      when "channel"    then ::Conversation.where(channel_id: @params[:channel_id])
      when "all"        then @user.admin? ? ::Conversation.all : ::Conversation.where(assignee_id: @user.id)
      else                   ::Conversation.where(assignee_id: @user.id) # mine
      end
    end

    def access_scope
      return ::Conversation.all if @user.admin?
      ::Conversation.where(channel_id: user_channel_ids)
    end

    def user_team_ids
      @user_team_ids ||= @user.teams.pluck(:id)
    end

    def user_channel_ids
      @user_channel_ids ||= @user.teams.joins(:channel_teams).pluck("channel_teams.channel_id").uniq
    end
  end
end
