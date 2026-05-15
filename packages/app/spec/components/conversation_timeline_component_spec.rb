require "rails_helper"

RSpec.describe ConversationTimelineComponent, type: :component do
  def make_channel
    Channel.create!(channel_type: "whatsapp_cloud", identifier: "id-#{SecureRandom.hex(4)}", name: "WhatsApp BR")
  end

  let(:channel) { make_channel }
  let(:contact) { Contact.create!(name: "Maria Silva") }
  let(:cc) { ContactChannel.create!(channel: channel, contact: contact, source_id: "s-#{SecureRandom.hex(3)}") }
  let(:conv) do
    Conversation.create!(channel: channel, contact: contact, contact_channel: cc,
      display_id: SecureRandom.random_number(1_000_000) + 1,
      status: "queued", last_activity_at: Time.current)
  end

  def make_message(content:, created_at:, direction: "inbound")
    Message.create!(conversation: conv, channel: channel, content: content,
      direction: direction, content_type: "text", status: "received",
      created_at: created_at, external_id: "ext-#{SecureRandom.hex(4)}",
      sender_type: "Contact", sender_id: contact.id)
  end

  it "interleaves messages and events in chronological order" do
    t0 = 1.hour.ago
    make_message(content: "hi", created_at: t0)
    Event.create!(name: "conversations:assigned", subject: conv, payload: {}, created_at: t0 + 1.minute)
    make_message(content: "back at you", created_at: t0 + 2.minutes)

    html = render_inline(described_class.new(conversation: conv))
    text = html.text.gsub(/\s+/, " ")
    expect(text.index("hi")).to be < text.index("Assigned")
    expect(text.index("Assigned")).to be < text.index("back at you")
  end

  it "filters out events not in the whitelist (noise reduction)" do
    Event.create!(name: "messages:inbound", subject: conv, payload: {})
    html = render_inline(described_class.new(conversation: conv))
    expect(html.text).not_to include("messages:inbound")
  end
end
