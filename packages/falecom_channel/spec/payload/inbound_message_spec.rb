require "spec_helper"

RSpec.describe FaleComChannel::Payload::InboundMessage do
  let(:valid_input) { FaleComChannel::Fixtures.inbound_message }

  it "accepts the canonical ARCHITECTURE.md inbound_message example" do
    struct = described_class.new(valid_input)
    expect(struct.type).to eq("inbound_message")
    expect(struct.channel.type).to eq("whatsapp_cloud")
    expect(struct.channel.identifier).to eq("5511999999999")
    expect(struct.contact.source_id).to eq("5511888888888")
    expect(struct.message.external_id).to eq("wamid.HBgLNtest123")
    expect(struct.message.direction).to eq("inbound")
    expect(struct.message.content).to eq("Oi, bom dia")
    expect(struct.message.content_type).to eq("text")
    expect(struct.message.sent_at).to eq("2026-04-16T14:32:00Z")
  end

  it "rejects when channel.type is missing" do
    input = valid_input.dup
    input[:channel] = {identifier: "5511999999999"}
    expect { described_class.new(input) }.to raise_error(Dry::Struct::Error)
  end

  it "rejects when channel.identifier is missing" do
    input = valid_input.dup
    input[:channel] = {type: "whatsapp_cloud"}
    expect { described_class.new(input) }.to raise_error(Dry::Struct::Error)
  end

  it "rejects when contact.source_id is missing" do
    input = valid_input.dup
    input[:contact] = {name: "João Silva"}
    expect { described_class.new(input) }.to raise_error(Dry::Struct::Error)
  end

  it "rejects when message.external_id is missing" do
    input = valid_input.dup
    input[:message] = valid_input[:message].except(:external_id)
    expect { described_class.new(input) }.to raise_error(Dry::Struct::Error)
  end

  it "rejects when message.direction is not inbound or outbound" do
    input = valid_input.dup
    input[:message] = valid_input[:message].merge(direction: "sideways")
    expect { described_class.new(input) }.to raise_error(Dry::Struct::Error)
  end

  it "rejects when message.content_type is outside the allowed list" do
    input = valid_input.dup
    input[:message] = valid_input[:message].merge(content_type: "unknown_type")
    expect { described_class.new(input) }.to raise_error(Dry::Struct::Error)
  end

  it "rejects when message.sent_at is missing" do
    input = valid_input.dup
    input[:message] = valid_input[:message].except(:sent_at)
    expect { described_class.new(input) }.to raise_error(Dry::Struct::Error)
  end

  it "defaults attachments to [] when omitted" do
    input = valid_input.dup
    input[:message] = valid_input[:message].except(:attachments)
    struct = described_class.new(input)
    expect(struct.message.attachments).to eq([])
  end

  it "defaults metadata to {} when omitted" do
    input = valid_input.except(:metadata)
    struct = described_class.new(input)
    expect(struct.metadata).to eq({})
  end

  it "accepts optional contact fields (name, phone_number, email, avatar_url)" do
    input = valid_input.dup
    input[:contact] = {
      source_id: "5511888888888",
      name: "Maria",
      phone_number: "+5511777777777",
      email: "maria@example.com",
      avatar_url: "https://example.com/maria.jpg"
    }
    struct = described_class.new(input)
    expect(struct.contact.name).to eq("Maria")
    expect(struct.contact.phone_number).to eq("+5511777777777")
    expect(struct.contact.email).to eq("maria@example.com")
    expect(struct.contact.avatar_url).to eq("https://example.com/maria.jpg")
  end

  it "accepts reply_to_external_id" do
    input = valid_input.dup
    input[:message] = valid_input[:message].merge(reply_to_external_id: "wamid.original123")
    struct = described_class.new(input)
    expect(struct.message.reply_to_external_id).to eq("wamid.original123")
  end

  it "preserves raw verbatim when present" do
    struct = described_class.new(valid_input)
    expect(struct.raw).to eq({provider_payload: "verbatim original"})
  end
end
