require "rails_helper"

RSpec.describe ConversationListRowComponent, type: :component do
  def make_channel
    Channel.create!(channel_type: "whatsapp_cloud", identifier: "id-#{SecureRandom.hex(4)}", name: "WhatsApp BR")
  end

  let(:channel) { make_channel }
  let(:contact) { Contact.create!(name: "Maria Silva") }
  let(:assignee) { User.create!(name: "Pedro", email_address: "p-#{SecureRandom.hex(3)}@x.test", password: "password", role: "agent", availability: "online") }
  let(:cc) { ContactChannel.create!(channel: channel, contact: contact, source_id: "s-#{SecureRandom.hex(3)}") }
  let(:conv) do
    Conversation.create!(channel: channel, contact: contact, contact_channel: cc,
      display_id: SecureRandom.random_number(1_000_000) + 1,
      status: "assigned", assignee: assignee, last_activity_at: 5.minutes.ago)
  end
  let!(:last_msg) do
    Message.create!(conversation: conv, channel: channel, content: "ok, sending now",
      direction: "outbound", content_type: "text", status: "sent", created_at: 5.minutes.ago,
      external_id: "ext-#{SecureRandom.hex(3)}")
  end

  it "renders contact name, last message preview, time, status badge" do
    html = render_inline(described_class.new(conversation: conv, active: false))
    expect(html.text).to include("Maria Silva")
    expect(html.text).to include("ok, sending now")
    expect(html.css(".status-badge.assigned")).not_to be_empty
  end

  it "marks active state visually" do
    html = render_inline(described_class.new(conversation: conv, active: true))
    expect(html.css(".row-active")).not_to be_empty
  end

  it "renders unread styling when unread: true" do
    html = render_inline(described_class.new(conversation: conv, active: false, unread: true))
    expect(html.css(".row-unread")).not_to be_empty
  end
end
