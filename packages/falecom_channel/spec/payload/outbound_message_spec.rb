require "spec_helper"

RSpec.describe FaleComChannel::Payload::OutboundMessage do
  let(:valid_input) { FaleComChannel::Fixtures.outbound_message }

  it "accepts a valid outbound_message dispatch payload" do
    struct = described_class.new(valid_input)
    expect(struct.type).to eq("outbound_message")
    expect(struct.channel.type).to eq("whatsapp_cloud")
    expect(struct.contact.source_id).to eq("5511888888888")
    expect(struct.message.internal_id).to eq(12345)
    expect(struct.message.content).to eq("Obrigado pelo contato!")
    expect(struct.message.content_type).to eq("text")
  end

  it "rejects when message.internal_id is missing" do
    input = valid_input.dup
    input[:message] = valid_input[:message].except(:internal_id)
    expect { described_class.new(input) }.to raise_error(Dry::Struct::Error)
  end

  it "rejects when contact.source_id is missing" do
    input = valid_input.dup
    input[:contact] = {}
    expect { described_class.new(input) }.to raise_error(Dry::Struct::Error)
  end

  it "defaults attachments to [] when omitted" do
    input = valid_input.dup
    input[:message] = valid_input[:message].except(:attachments)
    struct = described_class.new(input)
    expect(struct.message.attachments).to eq([])
  end

  it "accepts reply_to_external_id" do
    struct = described_class.new(valid_input)
    expect(struct.message.reply_to_external_id).to eq("wamid.HBgLNtest123")
  end
end
