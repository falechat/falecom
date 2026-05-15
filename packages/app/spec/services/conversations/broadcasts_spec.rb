require "rails_helper"

RSpec.describe Conversations::Broadcasts do
  def make_user
    User.create!(
      name: "U-#{SecureRandom.hex(3)}",
      email_address: "u-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      role: "agent"
    )
  end

  def make_channel
    Channel.create!(
      channel_type: "whatsapp_cloud",
      identifier: "id-#{SecureRandom.hex(4)}",
      name: "WA"
    )
  end

  def make_conversation(channel:, assignee: nil)
    contact = Contact.create!(name: "C-#{SecureRandom.hex(3)}")
    cc = ContactChannel.create!(channel: channel, contact: contact, source_id: "src-#{SecureRandom.hex(4)}")
    Conversation.create!(
      channel: channel,
      contact: contact,
      contact_channel: cc,
      display_id: SecureRandom.random_number(1_000_000) + 1,
      status: assignee ? "assigned" : "queued",
      assignee: assignee
    )
  end

  def make_message(conversation:, direction: "inbound", status: "received")
    Message.create!(
      conversation: conversation,
      channel: conversation.channel,
      direction: direction,
      content: "hi",
      content_type: "text",
      status: status,
      sender_type: "Contact",
      sender_id: conversation.contact.id
    )
  end

  let(:channel) { make_channel }
  let(:user) { make_user }
  let(:conv) { make_conversation(channel: channel, assignee: user) }

  it "message_appended broadcasts to conversation timeline and channel row" do
    msg = make_message(conversation: conv)
    expect { described_class.message_appended(msg) }
      .to have_broadcasted_to("conversation:#{conv.id}")
      .from_channel(Turbo::StreamsChannel)
      .and have_broadcasted_to("conversations:channel:#{channel.id}")
      .from_channel(Turbo::StreamsChannel)
  end

  it "assigned broadcasts to assignee's personal stream and the channel stream" do
    expect { described_class.assigned(conv) }
      .to have_broadcasted_to("conversations:user:#{user.id}")
      .from_channel(Turbo::StreamsChannel)
      .and have_broadcasted_to("conversations:channel:#{channel.id}")
      .from_channel(Turbo::StreamsChannel)
  end

  it "transferred removes from old user and appends to new user" do
    old_user = make_user
    expect { described_class.transferred(conv, from_user_id: old_user.id, from_team_id: nil) }
      .to have_broadcasted_to("conversations:user:#{old_user.id}")
      .from_channel(Turbo::StreamsChannel)
      .and have_broadcasted_to("conversations:user:#{user.id}")
      .from_channel(Turbo::StreamsChannel)
  end

  it "resolved broadcasts to channel stream and removes from assignee's stream" do
    expect { described_class.resolved(conv) }
      .to have_broadcasted_to("conversations:channel:#{channel.id}")
      .from_channel(Turbo::StreamsChannel)
      .and have_broadcasted_to("conversations:user:#{user.id}")
      .from_channel(Turbo::StreamsChannel)
  end

  it "message_status_changed targets timeline + row" do
    msg = make_message(conversation: conv, direction: "outbound", status: "delivered")
    expect { described_class.message_status_changed(msg) }
      .to have_broadcasted_to("conversation:#{conv.id}")
      .from_channel(Turbo::StreamsChannel)
      .and have_broadcasted_to("conversations:channel:#{channel.id}")
      .from_channel(Turbo::StreamsChannel)
  end
end
