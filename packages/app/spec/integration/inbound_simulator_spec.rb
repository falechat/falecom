require "rails_helper"
require "net/http"

# Requires the full inbound dev stack running:
#   docker compose up -d localstack dev-webhook meta-stub channel-whatsapp-cloud-consumer
# plus rake sqs:ensure_queues, plus this spec runs against a live Rails server
# (started outside the spec — pid file at tmp/pids/server.pid).
#
# Run with:
#   RUN_INTEGRATION=1 META_STUB_URL=http://meta-stub:4001 \
#   bundle exec rspec spec/integration/inbound_simulator_spec.rb
RSpec.describe "Inbound simulator end-to-end", :integration do
  self.use_transactional_tests = false

  after(:all) do
    if @channel
      Message.where(channel_id: @channel.id).delete_all
      Event.joins(:subject_message).where(messages: {channel_id: @channel.id}).delete_all rescue nil
      Conversation.where(channel_id: @channel.id).delete_all
      ContactChannel.where(channel_id: @channel.id).delete_all
      @channel.destroy
    end
  end

  let(:meta_stub_url) { ENV.fetch("META_STUB_URL", "http://meta-stub:4001") }
  let(:phone_number_id) { "15550000099" }
  let(:source_id) { "5511999999000" }

  before(:all) do
    @channel = Channel.find_or_create_by!(channel_type: "whatsapp_cloud", identifier: "15550000099") do |c|
      c.name = "E2E Sim"
      c.credentials = {access_token: "t", phone_number_id: "15550000099"}
    end
    Timeout.timeout(15) do
      until (Net::HTTP.get_response(URI.join(ENV.fetch("META_STUB_URL", "http://meta-stub:4001"), "/health")).code == "200" rescue false)
        sleep 0.5
      end
    end
  end

  def post_json(path, hash)
    uri = URI.join(meta_stub_url, path)
    res = Net::HTTP.post(uri, JSON.generate(hash), "Content-Type" => "application/json")
    [res.code.to_i, JSON.parse(res.body)]
  end

  def wait_for(timeout: 15)
    Timeout.timeout(timeout) do
      loop do
        result = yield
        return result if result
        sleep 0.3
      end
    end
  end

  it "drives inbound text from simulator through to a persisted Message" do
    content = "sim e2e #{SecureRandom.hex(4)}"
    code, body = post_json("/simulate/inbound", phone_number_id: phone_number_id, source_id: source_id, content: content)
    expect(code).to eq(200), "simulator returned #{code}: #{body.inspect}"
    expect(body.dig("body", "status")).to eq("enqueued")

    message = wait_for { Message.find_by(content: content) }
    expect(message.direction).to eq("inbound")
    expect(message.channel_id).to eq(@channel.id)
    expect(message.external_id).to start_with("wamid.SIM_")
    expect(message.conversation.contact_channel.source_id).to eq(source_id)
  end

  it "drives outbound status updates from simulator through to ProcessStatusUpdate" do
    contact = Contact.create!(name: "Status Tester")
    contact_channel = ContactChannel.find_or_create_by!(channel: @channel, contact: contact, source_id: "5511888888#{rand(1000)}")
    conv = @channel.conversations.create!(contact: contact, contact_channel: contact_channel,
      status: "queued", display_id: rand(10_000), last_activity_at: Time.current)
    ext = "wamid.SIM_STATUS_#{SecureRandom.hex(4)}"
    msg = Message.create!(channel: @channel, conversation: conv, direction: "outbound",
      status: "pending", content: "out", content_type: "text", external_id: ext)

    code, _ = post_json("/simulate/status", phone_number_id: phone_number_id, external_id: ext, status: "delivered")
    expect(code).to eq(200)

    wait_for { msg.reload.status == "delivered" or nil }
    expect(msg.status).to eq("delivered")
  end
end
