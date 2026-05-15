class Dashboard::ConversationsController < ApplicationController
  def index
    @view = params[:view].presence || "mine"
    @page = params[:page].to_i
    @scope = Conversations::Scope.call(user: Current.user, params: {view: @view, channel_id: params[:channel_id]})
    @active = nil
    @contact = nil
  end

  def show
    @conversation = Conversation.find(params[:id])
    unless ConversationPolicy.new(Current.user, @conversation).can_view?
      head :forbidden
      return
    end
    @view = params[:view].presence || "mine"
    @page = params[:page].to_i
    @scope = Conversations::Scope.call(user: Current.user, params: {view: @view, channel_id: params[:channel_id]})
    @active = @conversation
    @contact = @conversation.contact
    @messages = @conversation.messages.order(:id)
  end
end
