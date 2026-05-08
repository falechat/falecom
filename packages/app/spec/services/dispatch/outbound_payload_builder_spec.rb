require "rails_helper"

RSpec.describe Dispatch::OutboundPayloadBuilder do
  let(:channel) do
    Channel.create!(
      channel_type: "whatsapp_cloud",
      identifier: "wa-1",
      name: "WA",
      credentials: {access_token: "tok", phone_number_id: "pn-1"}
    )
  end
  let(:contact) { Contact.create!(name: "Jane") }
  let(:contact_channel) { ContactChannel.create!(channel: channel, contact: contact, source_id: "55119") }
  let(:conversation) do
    channel.conversations.create!(
      contact: contact,
      contact_channel: contact_channel,
      status: "queued",
      display_id: 1,
      last_activity_at: Time.current
    )
  end
  let(:message) do
    Message.create!(
      channel: channel,
      conversation: conversation,
      direction: "outbound",
      status: "pending",
      content: "hi",
      content_type: "text",
      reply_to_external_id: "wamid.123",
      metadata: {"foo" => "bar"}
    )
  end

  it "builds an outbound_message payload with channel/contact/message blocks" do
    payload = described_class.call(message)

    expect(payload[:type]).to eq("outbound_message")
    expect(payload[:channel]).to eq(type: "whatsapp_cloud", identifier: "wa-1")
    expect(payload[:contact]).to eq(source_id: "55119")
    expect(payload[:message]).to include(
      internal_id: message.id,
      content: "hi",
      content_type: "text",
      attachments: [],
      reply_to_external_id: "wamid.123"
    )
  end

  it "merges decrypted channel.credentials into metadata.channel_credentials" do
    payload = described_class.call(message)

    expect(payload[:metadata]).to include("foo" => "bar")
    expect(payload[:metadata]["channel_credentials"]).to eq("access_token" => "tok", "phone_number_id" => "pn-1")
  end

  it "passes FaleComChannel::Payload.validate! for the outbound shape" do
    payload = described_class.call(message)
    expect { FaleComChannel::Payload.validate!(payload) }.not_to raise_error
  end
end
