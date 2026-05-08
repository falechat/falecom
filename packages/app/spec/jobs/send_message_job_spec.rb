require "rails_helper"

RSpec.describe SendMessageJob do
  let(:channel) do
    Channel.create!(channel_type: "whatsapp_cloud", identifier: "wa-1", name: "WA",
      credentials: {access_token: "tok", phone_number_id: "pn-1"})
  end
  let(:contact) { Contact.create!(name: "Jane") }
  let(:contact_channel) { ContactChannel.create!(channel: channel, contact: contact, source_id: "55119") }
  let(:conversation) do
    channel.conversations.create!(contact: contact, contact_channel: contact_channel,
      status: "queued", display_id: 1, last_activity_at: Time.current)
  end
  let(:message) do
    Message.create!(channel: channel, conversation: conversation,
      direction: "outbound", status: "pending", content: "hi", content_type: "text")
  end

  before do
    stub_const("ENV", ENV.to_h.merge(
      "CHANNEL_WHATSAPP_CLOUD_URL" => "http://wa:9292",
      "FALECOM_DISPATCH_HMAC_SECRET" => "s"
    ))
  end

  it "POSTs via DispatchClient and marks message sent" do
    fake = stub_dispatch_client(response: {"external_id" => "ext-9"})

    described_class.perform_now(message.id)

    expect(fake).to have_received(:send_message).with(hash_including(type: "outbound_message"))
    expect(message.reload).to have_attributes(status: "sent", external_id: "ext-9")
  end

  it "emits messages:sent on success" do
    stub_dispatch_client
    expect { described_class.perform_now(message.id) }
      .to change { Event.where(name: "messages:sent", subject: message).count }.by(1)
  end

  it "is idempotent for already-sent messages" do
    message.update!(status: "sent", external_id: "ext-prior")
    fake = stub_dispatch_client
    described_class.perform_now(message.id)
    expect(fake).not_to have_received(:send_message)
  end

  it "discards on RecordNotFound" do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end

  it "reschedules on Faraday::Error and leaves message pending" do
    stub_dispatch_client(raise_error: Faraday::ConnectionFailed.new("boom"))
    expect {
      described_class.perform_now(message.id)
    }.to have_enqueued_job(described_class).with(message.id)
    expect(message.reload.status).to eq("pending")
  end

  it "marks message failed on terminal non-Faraday error" do
    stub_dispatch_client(raise_error: ArgumentError.new("malformed"))
    expect { described_class.perform_now(message.id) }.not_to raise_error
    expect(message.reload).to have_attributes(status: "failed", error: "malformed")
    expect(Event.where(name: "messages:failed", subject: message)).to exist
  end
end
