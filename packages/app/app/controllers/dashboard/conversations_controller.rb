class Dashboard::ConversationsController < ApplicationController
  def index
    @conversations = Conversation.order(last_activity_at: :desc).limit(50)
  end

  def show
    @conversation = Conversation.find(params[:id])
    @messages = @conversation.messages.order(:id)
  end
end
