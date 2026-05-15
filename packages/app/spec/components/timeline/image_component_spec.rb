require "rails_helper"

RSpec.describe "timeline/image partial", type: :component do
  def make_channel
    Channel.create!(channel_type: "whatsapp_cloud", identifier: "id-#{SecureRandom.hex(4)}", name: "WhatsApp")
  end

  let(:channel) { make_channel }
  let(:contact) { Contact.create!(name: "Maria") }
  let(:cc) { ContactChannel.create!(channel: channel, contact: contact, source_id: "s-#{SecureRandom.hex(3)}") }
  let(:conv) do
    Conversation.create!(channel: channel, contact: contact, contact_channel: cc,
      display_id: SecureRandom.random_number(1_000_000) + 1, status: "queued",
      last_activity_at: Time.current)
  end

  it "renders <img> + caption" do
    msg = Message.create!(conversation: conv, channel: channel, content: nil,
      direction: "inbound", content_type: "image", status: "received",
      external_id: "ext-#{SecureRandom.hex(4)}", sender_type: "Contact", sender_id: contact.id,
      metadata: {"url" => "https://cdn/x.jpg", "caption" => "look"})
    html = render_inline(TimelineMessageComponent.new(message: msg))
    expect(html.css("img.timeline-image[src='https://cdn/x.jpg']")).not_to be_empty
    expect(html.text).to include("look")
  end
end
