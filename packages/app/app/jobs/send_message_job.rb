class SendMessageJob < ApplicationJob
  queue_as :outbound

  retry_on FaleComChannel::RetryableDispatchError, wait: :polynomially_longer, attempts: 5
  retry_on Faraday::Error, wait: :polynomially_longer, attempts: 5
  discard_on ActiveRecord::RecordNotFound

  def perform(message_id)
    message = Message.find(message_id)
    return if message.status == "sent"

    payload = Dispatch::OutboundPayloadBuilder.call(message)
    container_url = Dispatch::ContainerUrlResolver.call(message.channel.channel_type)

    response = FaleComChannel::DispatchClient
      .new(container_url: container_url, secret: ENV.fetch("FALECOM_DISPATCH_HMAC_SECRET"))
      .send_message(payload)

    message.update!(external_id: response.fetch("external_id"), status: "sent")
    Events::Emit.call(name: "messages:sent", subject: message, actor: :system)
    Conversations::Broadcasts.message_status_changed(message)
  rescue Faraday::Error
    raise
  rescue => e
    message.update!(status: "failed", error: e.message)
    Events::Emit.call(name: "messages:failed", subject: message, actor: :system)
    Conversations::Broadcasts.message_status_changed(message)
  end
end
