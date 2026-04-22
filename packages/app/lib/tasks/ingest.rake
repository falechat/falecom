namespace :ingest do
  desc "Drive Ingestion::ProcessMessage with a mock inbound text payload. Usage: bin/rails 'ingest:mock[Hello from dev]'"
  task :mock, [:content] => :environment do |_t, args|
    channel = Channel.first || abort("No Channel found. Run bin/rails db:seed first.")
    content = args[:content].presence || "Mock message at #{Time.current.iso8601}"

    payload = {
      "type" => "inbound_message",
      "channel" => {"type" => channel.channel_type, "identifier" => channel.identifier},
      "contact" => {
        "source_id" => "mock_#{SecureRandom.hex(4)}",
        "name" => "Mock User"
      },
      "message" => {
        "external_id" => "MOCK_#{SecureRandom.hex(6)}",
        "direction" => "inbound",
        "content" => content,
        "content_type" => "text",
        "attachments" => [],
        "sent_at" => Time.current.iso8601
      },
      "metadata" => {},
      "raw" => {}
    }

    message = Ingestion::ProcessMessage.call(channel, payload)
    puts "Ingested Message##{message.id} on Conversation##{message.conversation_id}: #{content}"
  end
end
