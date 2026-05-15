module Dashboard
  module Conversations
    class PickupsController < ApplicationController
      def create
        conv = ::Conversation.find(params[:conversation_id])
        unless ConversationPolicy.new(Current.user, conv).can_pickup?
          head :forbidden
          return
        end
        team = (conv.channel.teams.to_a & Current.user.teams.to_a).first || conv.channel.teams.first
        ::Assignments::Transfer.call(
          conversation: conv,
          to_team: team,
          to_user: Current.user,
          actor: Current.user
        )
        redirect_to dashboard_conversation_path(conv)
      end
    end
  end
end
