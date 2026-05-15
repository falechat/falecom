require "rails_helper"

RSpec.describe Contacts::Create do
  let(:channel) { Channel.create!(channel_type: "whatsapp_cloud", identifier: "wa-#{SecureRandom.hex(3)}", name: "WA") }

  it "creates a bare contact when no channel/source_id" do
    contact = described_class.call(name: "Maria", phone_number: "+5511")
    expect(contact).to be_persisted
    expect(contact.name).to eq("Maria")
  end

  it "creates a contact with optional contact_channel" do
    contact = described_class.call(name: "Maria", phone_number: "+5511999", channel: channel, source_id: "5511999")
    expect(contact).to be_persisted
    expect(contact.contact_channels.where(channel: channel, source_id: "5511999")).to exist
  end

  it "reuses existing contact_channel" do
    existing = Contact.create!(name: "C")
    ContactChannel.create!(contact: existing, channel: channel, source_id: "src-x")
    contact = described_class.call(name: "Whatever", channel: channel, source_id: "src-x")
    expect(contact).to eq(existing)
  end
end
