require "rails_helper"

RSpec.describe AutoAssignJob, "depth guard" do
  let(:channel) { Channel.create!(channel_type: "whatsapp_cloud", identifier: "id-#{SecureRandom.hex(4)}", name: "WA") }
  let(:contact) { Contact.create!(name: "C") }
  let(:contact_channel) { ContactChannel.create!(channel: channel, contact: contact, source_id: "s-#{SecureRandom.hex(4)}") }
  let(:conversation) do
    Conversation.create!(
      channel: channel, contact: contact, contact_channel: contact_channel,
      display_id: SecureRandom.random_number(1_000_000) + 1, status: "queued"
    )
  end

  it "aborts silently when depth > MAX_DEPTH" do
    expect(Assignments::AutoAssign).not_to receive(:call)
    described_class.perform_now(conversation.id, depth: 4)
  end

  it "calls AutoAssign with depth: 0 by default" do
    expect(Assignments::AutoAssign).to receive(:call).with(conversation)
    described_class.perform_now(conversation.id)
  end

  it "passes through when depth <= MAX_DEPTH" do
    expect(Assignments::AutoAssign).to receive(:call).with(conversation)
    described_class.perform_now(conversation.id, depth: 3)
  end
end
