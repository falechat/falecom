require "rails_helper"

RSpec.describe Message, type: :model do
  let(:channel) { Channel.create!(channel_type: "whatsapp_cloud", identifier: "5511777777777", name: "WA Msg") }
  let(:contact) { Contact.create!(name: "Msg Contact") }
  let(:contact_channel) { ContactChannel.create!(channel: channel, contact: contact, source_id: "msg#{SecureRandom.hex(4)}") }
  let(:conversation) do
    Conversation.create!(
      channel: channel,
      contact: contact,
      contact_channel: contact_channel,
      display_id: 500
    )
  end
  let(:valid_attrs) do
    {
      conversation: conversation,
      channel: channel,
      direction: "inbound"
    }
  end

  it "belongs to conversation, channel" do
    conv_ref = Message.reflect_on_association(:conversation)
    expect(conv_ref).not_to be_nil
    expect(conv_ref.macro).to eq(:belongs_to)

    channel_ref = Message.reflect_on_association(:channel)
    expect(channel_ref).not_to be_nil
    expect(channel_ref.macro).to eq(:belongs_to)
  end

  it "has many_attached :attachments" do
    expect(Message.reflect_on_association(:attachments_attachments)).not_to be_nil
  end

  it "defines direction enum with inbound, outbound" do
    expect(Message.directions.keys).to eq(%w[inbound outbound])
  end

  it "defines content_type enum with text, image, audio, video, document, location, contact_card, input_select, button_reply, template" do
    expect(Message.content_types.keys).to eq(%w[text image audio video document location contact_card input_select button_reply template])
  end

  it "defines status enum with received, pending, sent, delivered, read, failed" do
    expect(Message.statuses.keys).to eq(%w[received pending sent delivered read failed])
  end

  it "defaults content_type to text, status to received" do
    msg = Message.create!(valid_attrs)
    expect(msg.content_type).to eq("text")
    expect(msg.status).to eq("received")
  end

  describe "#sender" do
    it "returns the User when sender_type is User" do
      user = User.create!(
        name: "Agent", email_address: "agent_msg@example.com",
        password: "password", role: "agent"
      )
      msg = Message.create!(valid_attrs.merge(sender_type: "User", sender_id: user.id))
      expect(msg.sender).to eq(user)
    end

    it "returns the Contact when sender_type is Contact" do
      msg = Message.create!(valid_attrs.merge(sender_type: "Contact", sender_id: contact.id))
      expect(msg.sender).to eq(contact)
    end

    it "returns nil when sender_type is Bot" do
      msg = Message.create!(valid_attrs.merge(sender_type: "Bot", sender_id: nil))
      expect(msg.sender).to be_nil
    end

    it "returns nil when sender_type is System" do
      msg = Message.create!(valid_attrs.merge(sender_type: "System", sender_id: nil))
      expect(msg.sender).to be_nil
    end
  end

  it "rejects invalid direction at the DB level via check constraint" do
    msg = Message.create!(valid_attrs)
    expect {
      Message.connection.execute(
        "UPDATE messages SET direction = 'bogus' WHERE id = #{msg.id}"
      )
    }.to raise_error(ActiveRecord::StatementInvalid, /messages_direction_check/)
  end

  it "rejects invalid content_type at the DB level via check constraint" do
    msg = Message.create!(valid_attrs)
    expect {
      Message.connection.execute(
        "UPDATE messages SET content_type = 'bogus' WHERE id = #{msg.id}"
      )
    }.to raise_error(ActiveRecord::StatementInvalid, /messages_content_type_check/)
  end

  it "rejects invalid status at the DB level via check constraint" do
    msg = Message.create!(valid_attrs)
    expect {
      Message.connection.execute(
        "UPDATE messages SET status = 'bogus' WHERE id = #{msg.id}"
      )
    }.to raise_error(ActiveRecord::StatementInvalid, /messages_status_check/)
  end

  it "enforces partial unique index on (channel_id, external_id) when external_id is present" do
    conv2 = Conversation.create!(
      channel: channel,
      contact: contact,
      contact_channel: ContactChannel.create!(channel: channel, contact: contact, source_id: "ext#{SecureRandom.hex(4)}"),
      display_id: 501,
      status: "resolved"
    )
    other_channel = Channel.create!(channel_type: "zapi", identifier: "5511666666666", name: "ZApi Msg")

    # Two messages with external_id nil on the same channel — both should succeed
    Message.create!(valid_attrs.merge(external_id: nil))
    Message.create!(valid_attrs.merge(external_id: nil))

    # Message with a real external_id — should succeed
    Message.create!(valid_attrs.merge(external_id: "wamid.XYZ"))

    # Another on the same channel with the same external_id — must raise
    expect {
      Message.create!(
        conversation: conv2,
        channel: channel,
        direction: "inbound",
        external_id: "wamid.XYZ"
      )
    }.to raise_error(ActiveRecord::RecordNotUnique)

    # Same external_id on a different channel — should succeed
    other_cc = ContactChannel.create!(channel: other_channel, contact: contact, source_id: "other#{SecureRandom.hex(4)}")
    other_conv = Conversation.create!(
      channel: other_channel,
      contact: contact,
      contact_channel: other_cc,
      display_id: 502
    )
    expect {
      Message.create!(
        conversation: other_conv,
        channel: other_channel,
        direction: "inbound",
        external_id: "wamid.XYZ"
      )
    }.not_to raise_error
  end
end
