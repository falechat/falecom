require "rails_helper"

RSpec.describe Dispatch::Outbound do
  let(:user) do
    User.create!(name: "Agent", email_address: "agent-#{SecureRandom.hex(4)}@x.test",
      password: "password", role: "agent")
  end
  let(:channel) { Channel.create!(channel_type: "whatsapp_cloud", identifier: "wa-1", name: "WA") }
  let(:contact) { Contact.create!(name: "Jane") }
  let(:contact_channel) { ContactChannel.create!(channel: channel, contact: contact, source_id: "55119") }
  let(:conversation) do
    channel.conversations.create!(contact: contact, contact_channel: contact_channel,
      status: "queued", display_id: 1, last_activity_at: Time.current)
  end

  it "creates an outbound Message with status: pending" do
    expect {
      described_class.call(conversation: conversation, content: "hi", actor: user)
    }.to change(Message, :count).by(1)

    msg = Message.last
    expect(msg).to have_attributes(direction: "outbound", status: "pending", content: "hi")
    expect(msg.sender).to eq(user)
  end

  it "enqueues SendMessageJob" do
    expect {
      described_class.call(conversation: conversation, content: "hi", actor: user)
    }.to have_enqueued_job(SendMessageJob)
  end

  it "emits messages:outbound" do
    expect {
      described_class.call(conversation: conversation, content: "hi", actor: user)
    }.to change { Event.where(name: "messages:outbound").count }.by(1)
  end

  it "passes reply_to_external_id through" do
    described_class.call(conversation: conversation, content: "hi", actor: user, reply_to_external_id: "wamid.x")
    expect(Message.last.reply_to_external_id).to eq("wamid.x")
  end

  it "accepts a symbol actor (e.g. :bot) and stores sender as nil" do
    described_class.call(conversation: conversation, content: "hi", actor: :bot)
    msg = Message.last
    expect(msg).to have_attributes(direction: "outbound", status: "pending", sender_id: nil, sender_type: nil)
  end

  def enqueued_jobs_for(klass)
    ActiveJob::Base.queue_adapter.enqueued_jobs.select { |j| j[:job] == klass }
  end
end
