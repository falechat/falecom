module FaleComChannel
  module Fixtures
    module_function

    def inbound_message
      {
        type: "inbound_message",
        channel: {
          type: "whatsapp_cloud",
          identifier: "5511999999999"
        },
        contact: {
          source_id: "5511888888888",
          name: "João Silva",
          phone_number: "+5511888888888",
          email: nil,
          avatar_url: "https://example.com/avatar.jpg"
        },
        message: {
          external_id: "wamid.HBgLNtest123",
          direction: "inbound",
          content: "Oi, bom dia",
          content_type: "text",
          attachments: [],
          sent_at: "2026-04-16T14:32:00Z",
          reply_to_external_id: nil
        },
        metadata: {
          whatsapp_context: {
            business_account_id: "123456789",
            phone_number_id: "987654321"
          },
          forwarded: false,
          quoted_message: nil
        },
        raw: {provider_payload: "verbatim original"}
      }
    end

    def outbound_status_update
      {
        type: "outbound_status_update",
        channel: {
          type: "whatsapp_cloud",
          identifier: "5511999999999"
        },
        external_id: "wamid.HBgLNtest123",
        status: "delivered",
        timestamp: "2026-04-16T14:32:05Z",
        error: nil,
        metadata: {}
      }
    end

    def outbound_message
      {
        type: "outbound_message",
        channel: {
          type: "whatsapp_cloud",
          identifier: "5511999999999"
        },
        contact: {
          source_id: "5511888888888"
        },
        message: {
          internal_id: 12345,
          content: "Obrigado pelo contato!",
          content_type: "text",
          attachments: [],
          reply_to_external_id: "wamid.HBgLNtest123"
        },
        metadata: {
          template_name: nil,
          template_params: nil
        }
      }
    end
  end
end
