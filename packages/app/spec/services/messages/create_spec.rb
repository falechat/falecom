require "rails_helper"

RSpec.describe Messages::Create do
  let(:channel) do
    Channel.create!(
      channel_type: "whatsapp_cloud",
      identifier: "+5511999999999",
      name: "WhatsApp Sales"
    )
  end
  let(:contact) { Contact.create!(name: "João") }
  let(:contact_channel) do
    ContactChannel.create!(channel: channel, contact: contact, source_id: "5511988888888")
  end
  let(:conversation) do
    channel.conversations.create!(
      contact: contact,
      contact_channel: contact_channel,
      status: "queued",
      display_id: 1,
      last_activity_at: Time.current
    )
  end

  let(:base_kwargs) do
    {
      conversation: conversation,
      direction: "inbound",
      content: "Olá",
      content_type: "text",
      status: "received",
      sender: contact,
      external_id: "WAMID.ABC",
      sent_at: Time.current
    }
  end

  it "inserts a Message with the provided attrs and returns it with #duplicate? == false" do
    message = described_class.call(**base_kwargs)

    expect(message).to be_persisted
    expect(message.channel_id).to eq(channel.id)
    expect(message.conversation_id).to eq(conversation.id)
    expect(message.direction).to eq("inbound")
    expect(message.external_id).to eq("WAMID.ABC")
    expect(message.status).to eq("received")
    expect(message.sender).to eq(contact)
    expect(message.duplicate?).to eq(false)
  end

  it "bumps conversation.last_activity_at" do
    before = 1.day.ago
    conversation.update!(last_activity_at: before)

    described_class.call(**base_kwargs)

    expect(conversation.reload.last_activity_at).to be > before
  end

  it "emits messages:inbound when direction == 'inbound'" do
    expect {
      described_class.call(**base_kwargs)
    }.to change { Event.where(name: "messages:inbound").count }.by(1)
  end

  it "emits messages:outbound when direction == 'outbound'" do
    expect {
      described_class.call(**base_kwargs.merge(direction: "outbound", status: "pending"))
    }.to change { Event.where(name: "messages:outbound").count }.by(1)
  end

  it "returns the existing record with #duplicate? == true on (channel_id, external_id) collision" do
    first = described_class.call(**base_kwargs)
    second = described_class.call(**base_kwargs.merge(content: "DUPLICATE"))

    expect(second.id).to eq(first.id)
    expect(second.content).to eq("Olá")
    expect(second.duplicate?).to eq(true)
    expect(Message.where(external_id: "WAMID.ABC").count).to eq(1)
  end

  it "emits no event on duplicate" do
    described_class.call(**base_kwargs)

    expect {
      described_class.call(**base_kwargs)
    }.not_to change { Event.count }
  end

  it "inserts without external_id when none given (system message path)" do
    message = described_class.call(
      conversation: conversation,
      direction: "outbound",
      content: "Transferência interna",
      content_type: "text",
      status: "received",
      sender: nil
    )

    expect(message).to be_persisted
    expect(message.external_id).to be_nil
    expect(message.sender).to be_nil
    expect(message.duplicate?).to eq(false)
  end
end
