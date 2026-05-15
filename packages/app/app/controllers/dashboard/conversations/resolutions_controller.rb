module Dashboard
  module Conversations
    class ResolutionsController < ApplicationController
      def create
        conv = ::Conversation.find(params[:conversation_id])
        ::Conversations::Resolve.call(conversation: conv, actor: Current.user)
        redirect_to dashboard_conversation_path(conv)
      rescue FaleCom::AuthorizationError
        head :forbidden
      end
    end
  end
end
