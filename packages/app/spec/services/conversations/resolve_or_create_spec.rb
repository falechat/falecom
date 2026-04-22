require "rails_helper"

RSpec.describe Conversations::ResolveOrCreate do
  let(:channel) do
    Channel.create!(channel_type: "whatsapp_cloud", identifier: "+5511999999999", name: "WhatsApp Sales")
  end
  let(:contact) { Contact.create!(name: "João") }
  let(:contact_channel) do
    ContactChannel.create!(channel: channel, contact: contact, source_id: "5511988888888")
  end

  describe ".call" do
    context "no conversations exist for this contact_channel" do
      it "creates a new conversation with status queued when the channel has no active flow" do
        conversation = described_class.call(channel, contact, contact_channel)

        expect(conversation).to be_persisted
        expect(conversation.status).to eq("queued")
        expect(conversation.display_id).to eq(1)
        expect(conversation.last_activity_at).to be_within(2.seconds).of(Time.current)
      end

      it "creates it with status bot when the channel has an active_flow_id" do
        channel.update!(active_flow_id: 1) # placeholder — FK not enforced until Spec 07 migration
        conversation = described_class.call(channel, contact, contact_channel)
        expect(conversation.status).to eq("bot")
      end

      it "emits conversations:created" do
        expect {
          described_class.call(channel, contact, contact_channel)
        }.to change { Event.where(name: "conversations:created").count }.by(1)
      end
    end

    context "an open conversation already exists for this contact_channel" do
      let!(:open_conversation) do
        channel.conversations.create!(
          contact: contact,
          contact_channel: contact_channel,
          status: "assigned",
          display_id: 7,
          last_activity_at: 1.hour.ago
        )
      end

      it "returns the existing open conversation" do
        conversation = described_class.call(channel, contact, contact_channel)
        expect(conversation.id).to eq(open_conversation.id)
      end

      it "emits no new conversations:created event" do
        expect {
          described_class.call(channel, contact, contact_channel)
        }.to change { Event.where(name: "conversations:created").count }.by(0)
      end
    end

    context "only resolved conversations exist" do
      before do
        channel.conversations.create!(
          contact: contact,
          contact_channel: contact_channel,
          status: "resolved",
          display_id: 3,
          last_activity_at: 1.day.ago
        )
      end

      it "creates a new conversation with the next display_id" do
        conversation = described_class.call(channel, contact, contact_channel)
        expect(conversation).to be_persisted
        expect(conversation.display_id).to eq(4)
      end
    end

    describe "display_id generation under concurrency" do
      it "serializes display_id assignment via an advisory lock (no duplicate display_ids)" do
        contact_b = Contact.create!(name: "Maria")
        contact_channel_b = ContactChannel.create!(channel: channel, contact: contact_b, source_id: "5511977777777")

        results = []
        threads = [
          Thread.new { ActiveRecord::Base.connection_pool.with_connection { results << described_class.call(channel, contact, contact_channel) } },
          Thread.new { ActiveRecord::Base.connection_pool.with_connection { results << described_class.call(channel, contact_b, contact_channel_b) } }
        ]
        threads.each(&:join)

        display_ids = results.map(&:display_id)
        expect(display_ids.sort).to eq([1, 2])
      end
    end
  end
end
