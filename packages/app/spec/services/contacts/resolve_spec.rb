require "rails_helper"

RSpec.describe Contacts::Resolve do
  let(:channel) do
    Channel.create!(channel_type: "whatsapp_cloud", identifier: "+5511999999999", name: "WhatsApp Sales")
  end

  describe ".call" do
    context "brand new (channel, source_id)" do
      let(:contact_data) do
        {"source_id" => "5511988888888", "name" => "João", "phone_number" => "+5511988888888"}
      end

      it "creates a Contact and a ContactChannel" do
        expect {
          described_class.call(channel, contact_data)
        }.to change { Contact.count }.by(1)
          .and change { ContactChannel.count }.by(1)
      end

      it "returns [contact, contact_channel]" do
        contact, contact_channel = described_class.call(channel, contact_data)

        expect(contact).to be_a(Contact)
        expect(contact_channel).to be_a(ContactChannel)
        expect(contact_channel.contact).to eq(contact)
        expect(contact_channel.channel).to eq(channel)
        expect(contact_channel.source_id).to eq("5511988888888")
      end

      it "emits contacts:created and contact_channels:created" do
        expect {
          described_class.call(channel, contact_data)
        }.to change { Event.where(name: "contacts:created").count }.by(1)
          .and change { Event.where(name: "contact_channels:created").count }.by(1)
      end
    end

    context "phone_number already matches an existing Contact" do
      let!(:existing_contact) { Contact.create!(name: "João Old", phone_number: "+5511988888888") }

      it "reuses the existing Contact, links a new ContactChannel" do
        contact, contact_channel = described_class.call(
          channel,
          {"source_id" => "5511988888888", "name" => "João", "phone_number" => "+5511988888888"}
        )

        expect(contact.id).to eq(existing_contact.id)
        expect(contact_channel.contact_id).to eq(existing_contact.id)
      end

      it "does NOT emit contacts:created (only contact_channels:created)" do
        expect {
          described_class.call(
            channel,
            {"source_id" => "5511988888888", "phone_number" => "+5511988888888"}
          )
        }.to change { Event.where(name: "contacts:created").count }.by(0)
          .and change { Event.where(name: "contact_channels:created").count }.by(1)
      end
    end

    context "existing (channel, source_id)" do
      let!(:contact) { Contact.create!(name: "João", phone_number: "+5511988888888") }
      let!(:contact_channel) do
        ContactChannel.create!(channel: channel, contact: contact, source_id: "5511988888888")
      end

      it "returns the existing pair without creating new records" do
        expect {
          described_class.call(channel, {"source_id" => "5511988888888", "name" => "João"})
        }.to change { Contact.count }.by(0)
          .and change { ContactChannel.count }.by(0)
      end

      it "emits nothing on re-resolve with identical data" do
        expect {
          described_class.call(channel, {"source_id" => "5511988888888", "name" => "João"})
        }.to change { Event.count }.by(0)
      end

      it "merges blank-to-populated fields but does not overwrite existing non-blank values" do
        described_class.call(
          channel,
          {
            "source_id" => "5511988888888",
            "name" => "OVERWRITE ATTEMPT",
            "email" => "joao@example.com"
          }
        )

        contact.reload
        expect(contact.name).to eq("João")                    # preserved
        expect(contact.email).to eq("joao@example.com")       # filled
      end
    end
  end
end
