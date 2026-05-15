class TimelineMessageComponent < ViewComponent::Base
  def initialize(message:)
    @message = message
  end

  attr_reader :message

  def alignment
    (@message.direction == "outbound") ? "outbound" : "inbound"
  end

  def content_partial
    case @message.content_type
    when "text" then "timeline/text"
    when "image" then "timeline/image"
    when "audio" then "timeline/audio"
    when "video" then "timeline/video"
    when "document" then "timeline/document"
    when "location" then "timeline/location"
    when "contact_card" then "timeline/contact_card"
    else "timeline/text"
    end
  end

  def status_icon
    return nil unless @message.direction == "outbound"
    {"pending" => "...", "sent" => "✓", "delivered" => "✓✓", "read" => "✓✓ (read)", "failed" => "!"}[@message.status]
  end
end
