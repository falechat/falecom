require "rails_helper"

RSpec.describe TransferModalComponent, type: :component do
  def make_user
    User.create!(name: "U-#{SecureRandom.hex(3)}", email_address: "u-#{SecureRandom.hex(4)}@x.test",
      password: "password", role: "agent", availability: "online")
  end

  let(:team_a) { Team.create!(name: "Sales") }
  let(:team_b) { Team.create!(name: "Finance") }
  let(:channel) do
    Channel.create!(channel_type: "whatsapp_cloud", identifier: "id-#{SecureRandom.hex(4)}", name: "WA").tap do |c|
      ChannelTeam.create!(channel: c, team: team_a)
      ChannelTeam.create!(channel: c, team: team_b)
    end
  end
  let(:user) { make_user.tap { |u| TeamMember.create!(user: u, team: team_a) } }
  let(:conv) do
    contact = Contact.create!(name: "C")
    cc = ContactChannel.create!(channel: channel, contact: contact, source_id: "src-#{SecureRandom.hex(4)}")
    Conversation.create!(channel: channel, contact: contact, contact_channel: cc,
      display_id: SecureRandom.random_number(1_000_000) + 1,
      status: "queued", team: team_a)
  end

  it "renders only teams attending the channel" do
    rendered = render_inline(described_class.new(conversation: conv, actor: user))
    options = rendered.css("select[name='transfer[to_team_id]'] option").map(&:text)
    expect(options).to include("Sales", "Finance")
  end

  it "renders the note textarea" do
    rendered = render_inline(described_class.new(conversation: conv, actor: user))
    expect(rendered.css("textarea[name='transfer[note]']")).not_to be_empty
  end
end
