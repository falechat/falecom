require "rails_helper"

RSpec.describe Conversation, type: :model do
  let(:channel) { Channel.create!(channel_type: "whatsapp_cloud", identifier: "5511999999999", name: "WA") }
  let(:contact) { Contact.create!(name: "X") }
  let(:contact_channel) { ContactChannel.create!(channel: channel, contact: contact, source_id: "abc#{SecureRandom.hex(4)}") }
  let(:valid_attrs) do
    {
      channel: channel,
      contact: contact,
      contact_channel: contact_channel,
      display_id: 1
    }
  end

  it "validates presence of display_id" do
    conv = Conversation.new(valid_attrs.except(:display_id))
    expect(conv.valid?).to be false
    expect(conv.errors[:display_id]).not_to be_empty
  end

  it "enforces uniqueness of display_id" do
    Conversation.create!(valid_attrs)
    expect {
      Conversation.create!(valid_attrs.merge(
        contact_channel: ContactChannel.create!(channel: channel, contact: contact, source_id: "other#{SecureRandom.hex(4)}"),
        display_id: 1,
        status: "resolved"
      ))
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "defines status enum with bot, queued, assigned, resolved" do
    expect(Conversation.statuses.keys).to eq(%w[bot queued assigned resolved])
  end

  it "defaults status to bot" do
    conv = Conversation.create!(valid_attrs)
    expect(conv.status).to eq("bot")
  end

  it "belongs to channel, contact, contact_channel" do
    channel_ref = Conversation.reflect_on_association(:channel)
    expect(channel_ref).not_to be_nil
    expect(channel_ref.macro).to eq(:belongs_to)

    contact_ref = Conversation.reflect_on_association(:contact)
    expect(contact_ref).not_to be_nil
    expect(contact_ref.macro).to eq(:belongs_to)

    contact_channel_ref = Conversation.reflect_on_association(:contact_channel)
    expect(contact_channel_ref).not_to be_nil
    expect(contact_channel_ref.macro).to eq(:belongs_to)
  end

  it "belongs to assignee (User) optionally" do
    ref = Conversation.reflect_on_association(:assignee)
    expect(ref).not_to be_nil
    expect(ref.macro).to eq(:belongs_to)
    expect(ref.options[:class_name]).to eq("User")
    expect(ref.options[:optional]).to be true
  end

  it "belongs to team optionally" do
    ref = Conversation.reflect_on_association(:team)
    expect(ref).not_to be_nil
    expect(ref.macro).to eq(:belongs_to)
    expect(ref.options[:optional]).to be true
  end

  it "has many messages" do
    ref = Conversation.reflect_on_association(:messages)
    expect(ref).not_to be_nil
    expect(ref.macro).to eq(:has_many)
  end

  it "enforces partial unique index: only one open conversation per contact_channel when status != resolved" do
    # First conversation on this contact_channel with status "resolved" — allowed
    cc = ContactChannel.create!(channel: channel, contact: contact, source_id: "partial#{SecureRandom.hex(4)}")
    Conversation.create!(
      channel: channel, contact: contact, contact_channel: cc,
      display_id: 100, status: "resolved"
    )

    # Second conversation on same contact_channel with status "bot" — allowed (only one non-resolved)
    Conversation.create!(
      channel: channel, contact: contact, contact_channel: cc,
      display_id: 101, status: "bot"
    )

    # Third on same contact_channel with status "queued" — must raise (already one non-resolved open)
    expect {
      Conversation.create!(
        channel: channel, contact: contact, contact_channel: cc,
        display_id: 102, status: "queued"
      )
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "rejects invalid status at the DB level via check constraint" do
    conv = Conversation.create!(valid_attrs)
    expect {
      Conversation.connection.execute(
        "UPDATE conversations SET status = 'bogus' WHERE id = #{conv.id}"
      )
    }.to raise_error(ActiveRecord::StatementInvalid, /conversations_status_check/)
  end
end
