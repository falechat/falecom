require "spec_helper"

RSpec.describe WhatsappCloud::Parser do
  let(:channel_identifier) { ENV.fetch("WHATSAPP_PHONE_NUMBER", "+15550000001") }

  describe ".to_common_payload" do
    it "maps a text inbound to the Common Ingestion Payload" do
      raw = JSON.generate(WhatsappCloud::Fixtures.inbound_text_webhook)
      payload = described_class.to_common_payload(raw)

      expect(payload["type"]).to eq("inbound_message")
      expect(payload["channel"]).to eq({"type" => "whatsapp_cloud", "identifier" => "15550000001"})
      expect(payload["contact"]).to include(
        "source_id" => "5511988888888",
        "name" => "João Silva"
      )
      expect(payload["message"]).to include(
        "external_id" => "wamid.HBgL1234567890",
        "direction" => "inbound",
        "content" => "Olá, tudo bem?",
        "content_type" => "text",
        "attachments" => []
      )
      expect(payload["message"]["sent_at"]).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      expect(payload["metadata"]["whatsapp_context"]["phone_number_id"]).to eq("PHONE_NUMBER_ID")
      expect(payload["raw"]).to be_a(Hash)
    end

    it "maps a status update to outbound_status_update" do
      raw = JSON.generate(WhatsappCloud::Fixtures.status_webhook(status: "read"))
      payload = described_class.to_common_payload(raw)

      expect(payload["type"]).to eq("outbound_status_update")
      expect(payload["channel"]).to eq({"type" => "whatsapp_cloud", "identifier" => "PHONE_NUMBER_ID"})
      expect(payload["external_id"]).to eq("wamid.HBgL1234567890")
      expect(payload["status"]).to eq("read")
      expect(payload["timestamp"]).to match(/\A\d{4}-\d{2}-\d{2}T/)
    end

    it "raises UnsupportedContentTypeError for non-text messages" do
      fixture = WhatsappCloud::Fixtures.inbound_text_webhook
      fixture["entry"][0]["changes"][0]["value"]["messages"][0]["type"] = "image"
      fixture["entry"][0]["changes"][0]["value"]["messages"][0].delete("text")

      expect {
        described_class.to_common_payload(JSON.generate(fixture))
      }.to raise_error(WhatsappCloud::Parser::UnsupportedContentTypeError, /image/)
    end
  end
end
