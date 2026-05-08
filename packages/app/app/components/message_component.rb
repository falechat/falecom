class MessageComponent < ViewComponent::Base
  def initialize(message:)
    @message = message
  end

  attr_reader :message
end
