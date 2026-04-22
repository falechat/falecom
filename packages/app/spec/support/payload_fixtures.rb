module PayloadFixtures
  module_function

  def inbound_text(overrides = {})
    {
      "type" => "inbound_message",
      "channel" => {"type" => "whatsapp_cloud", "identifier" => "+5511999999999"},
      "contact" => {
        "source_id" => "5511988888888",
        "name" => "João Silva",
        "phone_number" => "+5511988888888",
        "email" => nil,
        "avatar_url" => nil
      },
      "message" => {
        "external_id" => "WAMID.HBgL#{SecureRandom.hex(6)}",
        "direction" => "inbound",
        "content" => "Olá, gostaria de saber mais sobre o produto.",
        "content_type" => "text",
        "attachments" => [],
        "sent_at" => "2026-04-22T12:00:00Z",
        "reply_to_external_id" => nil
      },
      "metadata" => {
        "whatsapp_context" => {"business_account_id" => "123", "phone_number_id" => "456"}
      },
      "raw" => {"original" => "meta payload bytes would live here"}
    }.deep_merge(overrides)
  end

  def status_update(overrides = {})
    {
      "type" => "outbound_status_update",
      "channel" => {"type" => "whatsapp_cloud", "identifier" => "+5511999999999"},
      "external_id" => "WAMID.HBgL_ABC",
      "status" => "delivered",
      "timestamp" => "2026-04-22T12:05:00Z",
      "error" => nil,
      "metadata" => {}
    }.deep_merge(overrides)
  end
end
