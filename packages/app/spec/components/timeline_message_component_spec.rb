require "rails_helper"

RSpec.describe TimelineMessageComponent, type: :component do
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

  def make_msg(attrs = {})
    Message.create!({
      conversation: conv, channel: channel, content: "hi there",
      direction: "inbound", content_type: "text", status: "received",
      external_id: "ext-#{SecureRandom.hex(4)}",
      sender_type: "Contact", sender_id: contact.id
    }.merge(attrs))
  end

  it "renders inbound text left-aligned" do
    msg = make_msg
    html = render_inline(described_class.new(message: msg))
    expect(html.css(".bubble.inbound")).not_to be_empty
    expect(html.text).to include("hi there")
  end

  it "renders outbound text right-aligned with status checkmarks" do
    user = User.create!(name: "Op", email_address: "op-#{SecureRandom.hex(3)}@x.test", password: "password", role: "agent", availability: "online")
    msg = make_msg(direction: "outbound", content: "yo", status: "delivered", sender_type: "User", sender_id: user.id)
    html = render_inline(described_class.new(message: msg))
    expect(html.css(".bubble.outbound")).not_to be_empty
    expect(html.css(".status-delivered")).not_to be_empty
  end

  it "dispatches to image partial for image content_type" do
    msg = make_msg(content: nil, content_type: "image", metadata: {"url" => "https://cdn/x.jpg", "caption" => "look"})
    html = render_inline(described_class.new(message: msg))
    expect(html.css("img.timeline-image")).not_to be_empty
  end
end
