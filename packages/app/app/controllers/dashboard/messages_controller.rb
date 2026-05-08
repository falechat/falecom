class Dashboard::MessagesController < ApplicationController
  before_action :load_conversation
  before_action :authorize_reply

  def create
    content = params.require(:message).permit(:content)[:content].to_s.strip

    if content.empty?
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "reply-form-#{@conversation.id}",
            partial: "dashboard/conversations/reply_form",
            locals: {conversation: @conversation, error: "Message cannot be blank"}
          ), status: :unprocessable_entity
        end
        format.html { redirect_to dashboard_conversation_path(@conversation), alert: "Message cannot be blank" }
      end
      return
    end

    @message = Dispatch::Outbound.call(
      conversation: @conversation,
      content: content,
      actor: Current.user
    )

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to dashboard_conversation_path(@conversation) }
    end
  end

  private

  def load_conversation
    @conversation = Conversation.find(params[:conversation_id])
  end

  def authorize_reply
    head :forbidden unless Current.user&.can_reply_to?(@conversation)
  end
end
