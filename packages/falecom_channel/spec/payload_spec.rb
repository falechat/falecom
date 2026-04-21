require "spec_helper"
require "json"

RSpec.describe FaleComChannel::Payload do
  describe ".validate!" do
    it "dispatches to InboundMessage when type == \"inbound_message\"" do
      result = described_class.validate!(FaleComChannel::Fixtures.inbound_message)
      expect(result).to be_a(FaleComChannel::Payload::InboundMessage)
    end

    it "dispatches to OutboundStatusUpdate when type == \"outbound_status_update\"" do
      result = described_class.validate!(FaleComChannel::Fixtures.outbound_status_update)
      expect(result).to be_a(FaleComChannel::Payload::OutboundStatusUpdate)
    end

    it "dispatches to OutboundMessage when type == \"outbound_message\"" do
      result = described_class.validate!(FaleComChannel::Fixtures.outbound_message)
      expect(result).to be_a(FaleComChannel::Payload::OutboundMessage)
    end

    it "raises FaleComChannel::InvalidPayloadError on unknown type" do
      input = FaleComChannel::Fixtures.inbound_message.merge(type: "unknown_type")
      expect { described_class.validate!(input) }.to raise_error(FaleComChannel::InvalidPayloadError)
    end

    it "raises FaleComChannel::InvalidPayloadError when type is missing" do
      input = FaleComChannel::Fixtures.inbound_message.except(:type)
      expect { described_class.validate!(input) }.to raise_error(FaleComChannel::InvalidPayloadError)
    end

    it "accepts string-keyed hashes" do
      input = FaleComChannel::Fixtures.inbound_message
      string_keyed = JSON.parse(input.to_json) # converts all keys to strings
      result = described_class.validate!(string_keyed)
      expect(result).to be_a(FaleComChannel::Payload::InboundMessage)
    end
  end

  describe ".valid?" do
    it "returns true for the canonical fixtures and false for a mutated fixture" do
      expect(described_class.valid?(FaleComChannel::Fixtures.inbound_message)).to be(true)
      expect(described_class.valid?(FaleComChannel::Fixtures.outbound_status_update)).to be(true)
      expect(described_class.valid?(FaleComChannel::Fixtures.outbound_message)).to be(true)

      mutated = FaleComChannel::Fixtures.inbound_message.merge(type: "bogus")
      expect(described_class.valid?(mutated)).to be(false)
    end
  end

  describe ".parse" do
    it "returns a typed struct with accessor methods" do
      result = described_class.parse(FaleComChannel::Fixtures.inbound_message)
      expect(result).to be_a(FaleComChannel::Payload::InboundMessage)
      expect(result.type).to eq("inbound_message")
      expect(result.channel.type).to eq("whatsapp_cloud")
      expect(result.message.external_id).to eq("wamid.HBgLNtest123")
    end
  end
end
