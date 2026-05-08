require "securerandom"
require "time"

module MetaStub
  # Builds Meta WhatsApp Cloud webhook payloads matching the shape Meta sends
  # to subscribed apps. Used by the /simulate endpoints to drive the inbound
  # half of the pipeline without a real Meta account.
  module WebhookBuilder
    module_function

    # Inbound text message — entry[0].changes[0].value.messages[0]
    def inbound_text(phone_number_id:, source_id:, content:, contact_name: "Sim Tester")
      now = Time.now.to_i
      wamid = "wamid.SIM_#{SecureRandom.hex(8)}"
      {
        object: "whatsapp_business_account",
        entry: [{
          id: "WBA_SIM",
          changes: [{
            field: "messages",
            value: {
              messaging_product: "whatsapp",
              metadata: {display_phone_number: phone_number_id, phone_number_id: phone_number_id},
              contacts: [{profile: {name: contact_name}, wa_id: source_id}],
              messages: [{
                from: source_id,
                id: wamid,
                timestamp: now.to_s,
                type: "text",
                text: {body: content}
              }]
            }
          }]
        }]
      }
    end

    # Outbound status update — entry[0].changes[0].value.statuses[0]
    def outbound_status(phone_number_id:, external_id:, status:, recipient: "0000")
      now = Time.now.to_i
      {
        object: "whatsapp_business_account",
        entry: [{
          id: "WBA_SIM",
          changes: [{
            field: "messages",
            value: {
              messaging_product: "whatsapp",
              metadata: {display_phone_number: phone_number_id, phone_number_id: phone_number_id},
              statuses: [{
                id: external_id,
                status: status,
                timestamp: now.to_s,
                recipient_id: recipient
              }]
            }
          }]
        }]
      }
    end
  end
end
