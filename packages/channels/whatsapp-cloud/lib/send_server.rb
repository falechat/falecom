require "falecom_channel"
require_relative "sender"

module WhatsappCloud
  class SendServer < FaleComChannel::SendServer
    dispatch_secret ENV.fetch("FALECOM_DISPATCH_HMAC_SECRET", "dev-dispatch-secret")

    def handle_send(payload)
      meta = payload.metadata
      creds = meta[:channel_credentials] || meta["channel_credentials"] || {}
      sender = Sender.new(
        access_token: creds[:access_token] || creds["access_token"] || ENV.fetch("WHATSAPP_ACCESS_TOKEN"),
        phone_number_id: creds[:phone_number_id] || creds["phone_number_id"] || ENV.fetch("WHATSAPP_PHONE_NUMBER_ID")
      )
      payload_hash = JSON.parse(JSON.generate(payload.to_h))
      sender.send_message(payload_hash)
    end
  end
end
