require "rails_helper"

RSpec.describe ContactChannel, type: :model do
  it "belongs to contact" do
    reflection = ContactChannel.reflect_on_association(:contact)
    expect(reflection).not_to be_nil
    expect(reflection.macro).to eq(:belongs_to)
  end

  it "belongs to channel" do
    reflection = ContactChannel.reflect_on_association(:channel)
    expect(reflection).not_to be_nil
    expect(reflection.macro).to eq(:belongs_to)
  end

  it "validates presence of source_id" do
    channel = Channel.create!(channel_type: "whatsapp_cloud", identifier: "5511999999999", name: "Test Channel")
    contact = Contact.create!
    record = ContactChannel.new(channel: channel, contact: contact, source_id: "")
    expect(record.valid?).to be false
    expect(record.errors[:source_id]).not_to be_empty
  end

  it "enforces uniqueness of source_id scoped to channel_id" do
    channel = Channel.create!(channel_type: "whatsapp_cloud", identifier: "5511999999999", name: "Test Channel")
    contact_a = Contact.create!
    contact_b = Contact.create!

    ContactChannel.create!(channel: channel, contact: contact_a, source_id: "abc")

    # Same channel + same source_id on a different contact must raise
    expect {
      ContactChannel.create!(channel: channel, contact: contact_b, source_id: "abc")
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "allows the same source_id on different channels" do
    channel_a = Channel.create!(channel_type: "whatsapp_cloud", identifier: "5511111111111", name: "Channel A")
    channel_b = Channel.create!(channel_type: "zapi", identifier: "5522222222222", name: "Channel B")
    contact = Contact.create!

    ContactChannel.create!(channel: channel_a, contact: contact, source_id: "abc")
    expect {
      ContactChannel.create!(channel: channel_b, contact: contact, source_id: "abc")
    }.not_to raise_error
  end
end
