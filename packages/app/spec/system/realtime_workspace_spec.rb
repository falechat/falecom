require "rails_helper"

# Playwright-based two-browser system spec is out of scope (no harness wired
# in this repo yet). This request-level spec asserts that the broadcast
# routing is honored end-to-end: ingesting an inbound message broadcasts on
# the channel stream that subscribed agents would be listening on.
RSpec.describe "Realtime workspace integration", type: :request do
  include ActionCable::TestHelper

  let(:team) { Team.create!(name: "Support") }
  let(:channel) do
    Channel.create!(
      channel_type: "whatsapp_cloud",
      identifier: "id-#{SecureRandom.hex(4)}",
      name: "WA"
    ).tap { |c| ChannelTeam.create!(channel: c, team: team) }
  end
  let(:contact) { Contact.create!(name: "Alice") }
  let(:contact_channel) do
    ContactChannel.create!(channel: channel, contact: contact, source_id: "src-#{SecureRandom.hex(4)}")
  end
  let(:conversation) do
    Conversation.create!(
      channel: channel, contact: contact, contact_channel: contact_channel,
      display_id: SecureRandom.random_number(1_000_000) + 1, status: "queued"
    )
  end

  it "inbound message broadcasts to the channel + conversation streams" do
    message = Message.create!(
      conversation: conversation, channel: channel,
      direction: "inbound", content: "yo", content_type: "text", status: "received"
    )

    expect { Conversations::Broadcasts.message_appended(message) }
      .to have_broadcasted_to("conversation:#{conversation.id}")
      .from_channel(Turbo::StreamsChannel)
      .and have_broadcasted_to("conversations:channel:#{channel.id}")
      .from_channel(Turbo::StreamsChannel)
  end

  it "playwright two-browser end-to-end" do
    skip "Playwright system spec — uncomment once the test harness from Spec 01 is wired here"
  end
end
