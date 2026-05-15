class AutoAssignJob < ApplicationJob
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(conversation_id)
    Assignments::AutoAssign.call(Conversation.find(conversation_id))
  end
end
