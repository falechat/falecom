class TransferModalComponent < ViewComponent::Base
  def initialize(conversation:, actor:)
    @conversation = conversation
    @actor = actor
  end

  def teams
    @conversation.channel.teams.order(:name)
  end
end
