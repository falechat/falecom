class AvailabilityBadgeComponent < ViewComponent::Base
  COLOR = {
    "online" => "bg-green-500",
    "busy" => "bg-yellow-500",
    "offline" => "bg-gray-400"
  }.freeze

  def initialize(user:)
    @user = user
  end
end
