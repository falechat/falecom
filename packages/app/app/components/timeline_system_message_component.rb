class TimelineSystemMessageComponent < ViewComponent::Base
  def initialize(message:)
    @message = message
  end
end
