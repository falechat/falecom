require "spec_helper"

RSpec.describe WhatsappCloud::Sender do
  let(:access_token) { "EAAG-test-token" }
  let(:phone_number_id) { "PHONE_NUMBER_ID" }
  let(:sender) { described_class.new(access_token: access_token, phone_number_id: phone_number_id) }
  let(:payload) do
    {
      "type" => "outbound_message",
      "channel" => {"type" => "whatsapp_cloud", "identifier" => "15550000001"},
      "contact" => {"source_id" => "5511988888888"},
      "message" => {
        "internal_id" => 42,
        "content" => "Obrigado pelo contato!",
        "content_type" => "text",
        "attachments" => [],
        "reply_to_external_id" => nil
      },
      "metadata" => {}
    }
  end

  describe "#send_message" do
    let(:endpoint) { "https://graph.facebook.com/v21.0/#{phone_number_id}/messages" }

    it "POSTs to the Meta v21.0 /messages endpoint for a text message" do
      stub_request(:post, endpoint)
        .with(
          headers: {"Authorization" => "Bearer #{access_token}", "Content-Type" => "application/json"},
          body: hash_including(
            "messaging_product" => "whatsapp",
            "to" => "5511988888888",
            "type" => "text",
            "text" => {"body" => "Obrigado pelo contato!"}
          )
        )
        .to_return(status: 200, body: JSON.generate("messages" => [{"id" => "wamid.outbound.123"}]))

      result = sender.send_message(payload)
      expect(result).to eq(external_id: "wamid.outbound.123")
    end

    it "raises TerminalSendError for non-text content_type" do
      payload["message"]["content_type"] = "image"
      expect { sender.send_message(payload) }
        .to raise_error(WhatsappCloud::Sender::TerminalSendError, /image/)
    end

    it "raises TerminalSendError on 4xx" do
      stub_request(:post, endpoint).to_return(status: 400, body: JSON.generate("error" => {"message" => "invalid recipient"}))
      expect { sender.send_message(payload) }
        .to raise_error(WhatsappCloud::Sender::TerminalSendError, /invalid recipient/)
    end

    it "raises RetryableSendError on 5xx" do
      stub_request(:post, endpoint).to_return(status: 503, body: JSON.generate("error" => {"message" => "upstream"}))
      expect { sender.send_message(payload) }
        .to raise_error(WhatsappCloud::Sender::RetryableSendError, /upstream/)
    end

    it "raises TerminalSendError when 200 OK has no messages id" do
      stub_request(:post, endpoint).to_return(status: 200, body: "{}")
      expect { sender.send_message(payload) }
        .to raise_error(WhatsappCloud::Sender::TerminalSendError, /missing message id/i)
    end

    it "raises RetryableSendError on connection failure" do
      stub_request(:post, endpoint).to_raise(Faraday::ConnectionFailed.new("boom"))
      expect { sender.send_message(payload) }
        .to raise_error(WhatsappCloud::Sender::RetryableSendError, /boom/)
    end
  end

  describe "META_API_BASE override" do
    it "honors ENV[META_API_BASE] for default connection" do
      stub_const("ENV", ENV.to_h.merge("META_API_BASE" => "http://meta-stub:4000"))
      stub_request(:post, "http://meta-stub:4000/v21.0/#{phone_number_id}/messages")
        .to_return(status: 200, body: JSON.generate("messages" => [{"id" => "wamid.x"}]))
      result = sender.send_message(payload)
      expect(result).to eq(external_id: "wamid.x")
    end
  end
end
