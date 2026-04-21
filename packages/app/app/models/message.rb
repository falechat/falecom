class Message < ApplicationRecord
  belongs_to :conversation
  belongs_to :channel

  has_many_attached :attachments

  enum :direction, {inbound: "inbound", outbound: "outbound"}, validate: true
  enum :content_type, {
    text: "text",
    image: "image",
    audio: "audio",
    video: "video",
    document: "document",
    location: "location",
    contact_card: "contact_card",
    input_select: "input_select",
    button_reply: "button_reply",
    template: "template"
  }, validate: true
  enum :status, {
    received: "received",
    pending: "pending",
    sent: "sent",
    delivered: "delivered",
    read: "read",
    failed: "failed"
  }, validate: true

  def sender
    case sender_type
    when "User" then User.find_by(id: sender_id)
    when "Contact" then Contact.find_by(id: sender_id)
    when "Bot", "System" then nil
    end
  end
end
