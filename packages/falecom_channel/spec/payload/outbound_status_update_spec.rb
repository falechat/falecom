require "spec_helper"

RSpec.describe FaleComChannel::Payload::OutboundStatusUpdate do
  let(:valid_input) { FaleComChannel::Fixtures.outbound_status_update }

  it "accepts a valid delivered status update" do
    struct = described_class.new(valid_input)
    expect(struct.type).to eq("outbound_status_update")
    expect(struct.channel.type).to eq("whatsapp_cloud")
    expect(struct.external_id).to eq("wamid.HBgLNtest123")
    expect(struct.status).to eq("delivered")
    expect(struct.timestamp).to eq("2026-04-16T14:32:05Z")
  end

  it "rejects when external_id is missing" do
    input = valid_input.except(:external_id)
    expect { described_class.new(input) }.to raise_error(Dry::Struct::Error)
  end

  it "rejects when status is outside {sent, delivered, read, failed}" do
    input = valid_input.merge(status: "pending")
    expect { described_class.new(input) }.to raise_error(Dry::Struct::Error)
  end

  it "rejects when timestamp is missing" do
    input = valid_input.except(:timestamp)
    expect { described_class.new(input) }.to raise_error(Dry::Struct::Error)
  end

  it "accepts optional error string" do
    input = valid_input.merge(error: "Message delivery failed")
    struct = described_class.new(input)
    expect(struct.error).to eq("Message delivery failed")
  end
end
