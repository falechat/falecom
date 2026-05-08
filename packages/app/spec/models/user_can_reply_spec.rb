require "rails_helper"

RSpec.describe User, "#can_reply_to?" do
  let(:agent) do
    User.create!(name: "Agent", email_address: "a-#{SecureRandom.hex(4)}@x.test", password: "password", role: "agent")
  end
  let(:admin) do
    User.create!(name: "Admin", email_address: "ad-#{SecureRandom.hex(4)}@x.test", password: "password", role: "admin")
  end
  let(:channel) { Channel.create!(channel_type: "whatsapp_cloud", identifier: "wa-r", name: "WA") }
  let(:contact) { Contact.create!(name: "C") }
  let(:cc) { ContactChannel.create!(channel: channel, contact: contact, source_id: "111") }
  let(:conversation) do
    channel.conversations.create!(contact: contact, contact_channel: cc, status: "queued",
      display_id: rand(100_000), last_activity_at: Time.current, assignee: agent)
  end

  it "is true when user is the assignee" do
    expect(agent.can_reply_to?(conversation)).to be true
  end

  it "is true for admins regardless of assignee" do
    expect(admin.can_reply_to?(conversation)).to be true
  end

  it "is false for unrelated agents" do
    other = User.create!(name: "Other", email_address: "o-#{SecureRandom.hex(4)}@x.test", password: "password", role: "agent")
    expect(other.can_reply_to?(conversation)).to be false
  end
end
