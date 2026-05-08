require "rails_helper"
require "net/http"

RSpec.describe "Outbound dispatch end-to-end", :integration do
  include ActiveJob::TestHelper

  let(:user) do
    User.create!(name: "Agent", email_address: "agent-#{SecureRandom.hex(4)}@x.test",
      password: "password", role: "agent")
  end
  let(:channel) do
    Channel.create!(channel_type: "whatsapp_cloud", identifier: "wa-1", name: "WA",
      credentials: {access_token: "tok", phone_number_id: "pn-1"})
  end
  let(:contact) { Contact.create!(name: "Jane") }
  let(:contact_channel) { ContactChannel.create!(channel: channel, contact: contact, source_id: "55119") }
  let(:conversation) do
    channel.conversations.create!(contact: contact, contact_channel: contact_channel,
      status: "queued", display_id: 1, last_activity_at: Time.current)
  end

  before(:all) do
    base = ENV["CHANNEL_WHATSAPP_CLOUD_URL"] or raise "set CHANNEL_WHATSAPP_CLOUD_URL"
    Timeout.timeout(15) do
      loop do
        begin
          res = Net::HTTP.get_response(URI.join(base, "/health"))
          break if res.code == "200"
        rescue
        end
        sleep 0.5
      end
    end
  end

  it "delivers an outbound text message through the live container" do
    perform_enqueued_jobs do
      Dispatch::Outbound.call(conversation: conversation, content: "ping", actor: user)
    end

    msg = Message.where(conversation: conversation).order(:id).last
    expect(msg.status).to eq("sent")
    expect(msg.external_id).to start_with("wamid.test-")
  end
end
