require "rails_helper"

RSpec.describe StatusIndicatorComponent, type: :component do
  let(:channel) { Channel.create!(channel_type: "whatsapp_cloud", identifier: "wa-#{SecureRandom.hex(2)}", name: "WA") }
  let(:contact) { Contact.create!(name: "C") }
  let(:cc) { ContactChannel.create!(channel: channel, contact: contact, source_id: "1") }
  let(:conv) do
    channel.conversations.create!(contact: contact, contact_channel: cc, status: "queued",
      display_id: rand(1_000_000), last_activity_at: Time.current)
  end
  def msg(status, error: nil)
    Message.create!(channel: channel, conversation: conv, direction: "outbound",
      status: status, content: "x", content_type: "text", error: error)
  end

  {
    "pending" => {icon: "clock", color: "text-gray-400"},
    "sent" => {icon: "check", color: "text-gray-400"},
    "delivered" => {icon: "check-double", color: "text-gray-400"},
    "read" => {icon: "check-double", color: "text-blue-500"},
    "failed" => {icon: "exclamation", color: "text-red-500"}
  }.each do |status, expected|
    it "renders #{status} with icon=#{expected[:icon]} color=#{expected[:color]}" do
      m = msg(status, error: (status == "failed") ? "boom" : nil)
      render_inline(described_class.new(message: m))

      expect(page).to have_css(".#{expected[:color].tr(" ", ".")}")
      expect(page).to have_css("[data-icon='#{expected[:icon]}']")
      expect(page).to have_css("##{"message_#{m.id}_status"}")
    end
  end

  it "shows error in title for failed" do
    m = msg("failed", error: "rate limit")
    render_inline(described_class.new(message: m))
    expect(page).to have_css("[title='rate limit']")
  end
end
