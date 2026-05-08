require "spec_helper"

RSpec.describe MetaStub::WebhookBuilder do
  describe ".inbound_text" do
    it "produces a Meta-shaped messages webhook" do
      payload = described_class.inbound_text(phone_number_id: "PNID", source_id: "55119", content: "oi")
      message = payload.dig(:entry, 0, :changes, 0, :value, :messages, 0)

      expect(payload[:object]).to eq("whatsapp_business_account")
      expect(message[:from]).to eq("55119")
      expect(message[:type]).to eq("text")
      expect(message.dig(:text, :body)).to eq("oi")
      expect(message[:id]).to start_with("wamid.SIM_")
    end
  end

  describe ".outbound_status" do
    it "produces a status webhook for an existing external_id" do
      payload = described_class.outbound_status(phone_number_id: "PNID", external_id: "wamid.X", status: "delivered")
      status = payload.dig(:entry, 0, :changes, 0, :value, :statuses, 0)

      expect(status[:id]).to eq("wamid.X")
      expect(status[:status]).to eq("delivered")
    end
  end
end
