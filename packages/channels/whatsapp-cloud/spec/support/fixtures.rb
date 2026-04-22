module WhatsappCloud; end
module WhatsappCloud::Fixtures
  module_function

  def inbound_text_webhook
    {
      "object" => "whatsapp_business_account",
      "entry" => [{
        "id" => "BUSINESS_ACCOUNT_ID",
        "changes" => [{
          "field" => "messages",
          "value" => {
            "messaging_product" => "whatsapp",
            "metadata" => {
              "display_phone_number" => "15550000001",
              "phone_number_id" => "PHONE_NUMBER_ID"
            },
            "contacts" => [{
              "profile" => {"name" => "João Silva"},
              "wa_id" => "5511988888888"
            }],
            "messages" => [{
              "from" => "5511988888888",
              "id" => "wamid.HBgL1234567890",
              "timestamp" => "1745000000",
              "text" => {"body" => "Olá, tudo bem?"},
              "type" => "text"
            }]
          }
        }]
      }]
    }
  end

  def status_webhook(status: "delivered", external_id: "wamid.HBgL1234567890")
    {
      "object" => "whatsapp_business_account",
      "entry" => [{
        "id" => "BUSINESS_ACCOUNT_ID",
        "changes" => [{
          "field" => "messages",
          "value" => {
            "messaging_product" => "whatsapp",
            "metadata" => {"phone_number_id" => "PHONE_NUMBER_ID"},
            "statuses" => [{
              "id" => external_id,
              "status" => status,
              "timestamp" => "1745000005",
              "recipient_id" => "5511988888888"
            }]
          }
        }]
      }]
    }
  end
end
