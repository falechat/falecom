require "rails_helper"

RSpec.describe AutoAssignJob do
  let(:channel) do
    Channel.create!(channel_type: "whatsapp_cloud", identifier: "id-#{SecureRandom.hex(4)}", name: "WA")
  end
  let(:contact) { Contact.create!(name: "C") }
  let(:contact_channel) { ContactChannel.create!(channel: channel, contact: contact, source_id: "s-#{SecureRandom.hex(4)}") }
  let(:conversation) do
    Conversation.create!(
      channel: channel, contact: contact, contact_channel: contact_channel,
      display_id: SecureRandom.random_number(1_000_000) + 1, status: "queued"
    )
  end

  it "delegates to Assignments::AutoAssign" do
    expect(Assignments::AutoAssign).to receive(:call).with(conversation)
    described_class.perform_now(conversation.id)
  end

  it "discards on RecordNotFound" do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end
end
