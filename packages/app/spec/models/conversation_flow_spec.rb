require "rails_helper"

RSpec.describe ConversationFlow, type: :model do
  let(:channel) { Channel.create!(name: "c", channel_type: "whatsapp_cloud", identifier: "c-1") }
  let(:contact) { Contact.create!(name: "x") }
  let(:cc)      { ContactChannel.create!(contact: contact, channel: channel, source_id: "s") }
  let(:conv)    { Conversation.create!(channel: channel, contact: contact, contact_channel: cc, display_id: 1) }
  let(:flow)    { Flow.create!(name: "f") }

  it "validates status enum" do
    expect { ConversationFlow.create!(conversation: conv, flow: flow, status: "lol") }
      .to raise_error(ActiveRecord::RecordInvalid)
  end

  it "enforces one active flow per conversation" do
    ConversationFlow.create!(conversation: conv, flow: flow, status: "active")
    expect {
      ConversationFlow.create!(conversation: conv, flow: flow, status: "active")
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "allows multiple completed flows per conversation" do
    ConversationFlow.create!(conversation: conv, flow: flow, status: "completed")
    expect {
      ConversationFlow.create!(conversation: conv, flow: flow, status: "completed")
    }.not_to raise_error
  end

  it "defaults state to {}" do
    cf = ConversationFlow.create!(conversation: conv, flow: flow)
    expect(cf.state).to eq({})
    expect(cf.status).to eq("active")
  end
end
