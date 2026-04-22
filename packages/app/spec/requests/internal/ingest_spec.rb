require "rails_helper"

RSpec.describe "POST /internal/ingest", type: :request do
  let!(:channel) do
    Channel.create!(channel_type: "whatsapp_cloud", identifier: "+5511999999999", name: "WhatsApp Sales")
  end

  def post_ingest(payload)
    post "/internal/ingest", params: payload.to_json, headers: {"Content-Type" => "application/json"}
  end

  context "valid inbound_message" do
    it "returns 200 and persists a Message" do
      expect {
        post_ingest(PayloadFixtures.inbound_text)
      }.to change { Message.count }.by(1)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("ok")
      expect(body["message_id"]).to be_a(Integer)
    end
  end

  context "duplicate external_id" do
    it "returns 200 and does NOT create a second Message" do
      payload = PayloadFixtures.inbound_text
      post_ingest(payload)
      expect {
        post_ingest(payload)
      }.to change { Message.count }.by(0)
      expect(response).to have_http_status(:ok)
    end
  end

  context "unregistered channel identifier" do
    it "returns 422 and writes nothing" do
      payload = PayloadFixtures.inbound_text(
        "channel" => {"type" => "whatsapp_cloud", "identifier" => "+5500000000000"}
      )
      expect {
        post_ingest(payload)
      }.to change { Message.count }.by(0)
        .and change { Contact.count }.by(0)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  context "inactive channel" do
    before { channel.update!(active: false) }

    it "returns 422" do
      post_ingest(PayloadFixtures.inbound_text)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  context "schema-invalid payload (missing required field)" do
    it "returns 422" do
      payload = PayloadFixtures.inbound_text
      payload["message"].delete("external_id")
      post_ingest(payload)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  context "valid outbound_status_update" do
    let!(:message) do
      contact = Contact.create!(name: "João")
      contact_channel = ContactChannel.create!(channel: channel, contact: contact, source_id: "5511988888888")
      conversation = channel.conversations.create!(
        contact: contact, contact_channel: contact_channel,
        status: "assigned", display_id: 1, last_activity_at: Time.current
      )
      Message.create!(
        channel: channel, conversation: conversation, direction: "outbound",
        content: "Olá", content_type: "text", status: "sent",
        external_id: "WAMID.XYZ", sent_at: Time.current
      )
    end

    it "updates status and returns 200" do
      post_ingest(PayloadFixtures.status_update("external_id" => "WAMID.XYZ", "status" => "delivered"))
      expect(response).to have_http_status(:ok)
      expect(message.reload.status).to eq("delivered")
    end
  end

  context "status update for unknown external_id" do
    it "returns 422 so the container NACKs" do
      post_ingest(PayloadFixtures.status_update("external_id" => "WAMID.UNKNOWN", "status" => "delivered"))
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
