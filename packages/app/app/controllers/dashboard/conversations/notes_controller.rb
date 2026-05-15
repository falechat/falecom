module Dashboard
  module Conversations
    class NotesController < ApplicationController
      def create
        conv = ::Conversation.find(params[:conversation_id])
        unless ConversationPolicy.new(Current.user, conv).can_view?
          head :forbidden
          return
        end

        ::Messages::Create.call(
          conversation: conv,
          direction: "outbound",
          content: params.dig(:note, :content),
          content_type: "text",
          status: "received",
          sender: nil
        )

        redirect_to dashboard_conversation_path(conv)
      end
    end
  end
end
