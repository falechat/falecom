require "rails_helper"

RSpec.describe TimelineEventComponent, type: :component do
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

  it "renders 'Assigned to <user>' for conversations:assigned" do
    u = User.create!(name: "Maria", email_address: "m-#{SecureRandom.hex(3)}@x.test", password: "password", role: "agent", availability: "online")
    e = Event.create!(name: "conversations:assigned", subject: conv, payload: {"assignee_id" => u.id})
    html = render_inline(described_class.new(event: e))
    expect(html.text).to include("Maria")
  end

  it "renders 'Handed off to <team>' for flows:handoff" do
    team = Team.create!(name: "Finance")
    e = Event.create!(name: "flows:handoff", subject: conv, payload: {"team_id" => team.id})
    html = render_inline(described_class.new(event: e))
    expect(html.text).to include("Finance")
  end
end
