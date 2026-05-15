module Conversations
  class Resolve
    def self.call(conversation:, actor:)
      raise FaleCom::AuthorizationError unless ConversationPolicy.new(actor, conversation).can_resolve?
      conversation.update!(status: "resolved")
      Events::Emit.call(name: "conversations:resolved", subject: conversation, actor: actor)
      Conversations::Broadcasts.resolved(conversation)
      conversation
    end
  end
end
