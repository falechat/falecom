class AutoAssignJob < ApplicationJob
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  MAX_DEPTH = 3

  def perform(conversation_id, depth: 0)
    return if depth > MAX_DEPTH
    Assignments::AutoAssign.call(Conversation.find(conversation_id))
  end
end
