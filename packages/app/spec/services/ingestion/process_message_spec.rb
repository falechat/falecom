require "rails_helper"

RSpec.describe Ingestion::ProcessMessage do
  let(:channel) do
    Channel.create!(
      channel_type: "whatsapp_cloud",
      identifier: "+5511999999999",
      name: "WhatsApp Sales"
    )
  end

  describe ".call" do
    it "creates Contact, ContactChannel, Conversation, and Message and emits expected events" do
      payload = PayloadFixtures.inbound_text

      expect {
        described_class.call(channel, payload)
      }.to change { Contact.count }.by(1)
        .and change { ContactChannel.count }.by(1)
        .and change { Conversation.count }.by(1)
        .and change { Message.count }.by(1)

      names = Event.pluck(:name)
      expect(names).to include("contacts:created", "contact_channels:created", "conversations:created", "messages:inbound")
    end

    it "is idempotent on the same external_id — second call creates no new records and emits no new events" do
      payload = PayloadFixtures.inbound_text

      described_class.call(channel, payload)

      expect {
        described_class.call(channel, payload)
      }.to change { Message.count }.by(0)
        .and change { Event.count }.by(0)
    end

    it "appends to an existing open conversation when the contact messages again" do
      first = PayloadFixtures.inbound_text
      second = PayloadFixtures.inbound_text(
        "message" => {"external_id" => "WAMID.DIFFERENT", "content" => "Segunda"}
      )

      described_class.call(channel, first)
      expect {
        described_class.call(channel, second)
      }.to change { Conversation.count }.by(0)
        .and change { Message.count }.by(1)
    end

    it "creates a new conversation when the previous one is resolved" do
      first = PayloadFixtures.inbound_text
      described_class.call(channel, first)
      Conversation.last.update!(status: "resolved")

      second = PayloadFixtures.inbound_text(
        "message" => {"external_id" => "WAMID.NEWER", "content" => "Voltei"}
      )
      expect {
        described_class.call(channel, second)
      }.to change { Conversation.count }.by(1)
    end

    it "returns the persisted Message" do
      result = described_class.call(channel, PayloadFixtures.inbound_text)
      expect(result).to be_a(Message)
      expect(result).to be_persisted
    end
  end
end
