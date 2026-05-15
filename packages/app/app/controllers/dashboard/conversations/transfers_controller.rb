module Dashboard
  module Conversations
    class TransfersController < ApplicationController
      before_action :load_conversation

      def new
        if request.format.json?
          team = Team.find(params[:to_team_id])
          render json: {users: team.users.select(:id, :name)}
        else
          render TransferModalComponent.new(conversation: @conversation, actor: Current.user)
        end
      end

      def create
        ::Assignments::Transfer.call(
          conversation: @conversation,
          to_team: lookup(Team, params.dig(:transfer, :to_team_id)),
          to_user: lookup(User, params.dig(:transfer, :to_user_id)),
          note: params.dig(:transfer, :note).presence,
          actor: Current.user
        )
        redirect_to dashboard_conversation_path(@conversation)
      rescue FaleCom::AuthorizationError
        head :forbidden
      rescue FaleCom::ValidationError => e
        render plain: e.message, status: :unprocessable_content
      end

      private

      def load_conversation
        @conversation = ::Conversation.find(params[:conversation_id])
        unless ConversationPolicy.new(Current.user, @conversation).can_view?
          head :forbidden
          nil
        end
      end

      def lookup(klass, id) = id.present? ? klass.find(id) : nil
    end
  end
end
