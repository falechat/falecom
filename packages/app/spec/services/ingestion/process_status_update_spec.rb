require "rails_helper"

RSpec.describe Ingestion::ProcessStatusUpdate do
  let(:channel) do
    Channel.create!(channel_type: "whatsapp_cloud", identifier: "+5511999999999", name: "WhatsApp Sales")
  end
  let(:contact) { Contact.create!(name: "João") }
  let(:contact_channel) do
    ContactChannel.create!(channel: channel, contact: contact, source_id: "5511988888888")
  end
  let(:conversation) do
    channel.conversations.create!(
      contact: contact,
      contact_channel: contact_channel,
      status: "assigned",
      display_id: 1,
      last_activity_at: Time.current
    )
  end
  let!(:message) do
    Message.create!(
      channel: channel,
      conversation: conversation,
      direction: "outbound",
      content: "Olá",
      content_type: "text",
      status: "sent",
      external_id: "WAMID.ABC",
      sent_at: Time.current
    )
  end

  describe ".call" do
    it "updates the message status when the new status is later in the lifecycle" do
      payload = PayloadFixtures.status_update("external_id" => "WAMID.ABC", "status" => "delivered")
      result = described_class.call(channel, payload)

      expect(result).to eq(:updated)
      expect(message.reload.status).to eq("delivered")
    end

    it "emits messages:delivered on a real update" do
      payload = PayloadFixtures.status_update("external_id" => "WAMID.ABC", "status" => "delivered")
      expect {
        described_class.call(channel, payload)
      }.to change { Event.where(name: "messages:delivered").count }.by(1)
    end

    it "is a no-op when the new status is not later (delivered does not overwrite read)" do
      message.update!(status: "read")
      payload = PayloadFixtures.status_update("external_id" => "WAMID.ABC", "status" => "delivered")

      expect(described_class.call(channel, payload)).to eq(:noop)
      expect(message.reload.status).to eq("read")
    end

    it "sets error and marks failed when status == failed at any point" do
      payload = PayloadFixtures.status_update(
        "external_id" => "WAMID.ABC",
        "status" => "failed",
        "error" => "Meta rate limit"
      )

      expect(described_class.call(channel, payload)).to eq(:updated)
      expect(message.reload.status).to eq("failed")
      expect(message.error).to eq("Meta rate limit")
    end

    it "is a no-op on SQS redelivery of the same status" do
      message.update!(status: "delivered")
      payload = PayloadFixtures.status_update("external_id" => "WAMID.ABC", "status" => "delivered")

      expect(described_class.call(channel, payload)).to eq(:noop)
      expect { described_class.call(channel, payload) }.to change { Event.count }.by(0)
    end

    it "returns :retry when no message with that external_id exists on this channel" do
      payload = PayloadFixtures.status_update("external_id" => "WAMID.UNKNOWN", "status" => "delivered")

      expect(described_class.call(channel, payload)).to eq(:retry)
    end
  end
end
