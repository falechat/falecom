require "falecom_channel"
require_relative "lib/parser"
require_relative "lib/signature_verifier"
require_relative "lib/sender"

module WhatsappCloud
  class Container
    include FaleComChannel::Consumer

    queue_name ENV.fetch("SQS_QUEUE_NAME", "sqs-whatsapp-cloud")
    concurrency Integer(ENV.fetch("CONCURRENCY", "1"))

    def handle(raw_body, headers)
      signature = headers["X-Hub-Signature-256"] || headers[:x_hub_signature_256]
      SignatureVerifier.verify!(raw_body, signature.to_s)

      payload = Parser.to_common_payload(raw_body)
      FaleComChannel::Payload.validate!(payload.transform_keys(&:to_s))
      ingest_client.post(payload)
    end
  end
end

WhatsappCloud::Container.new.start if __FILE__ == $PROGRAM_NAME
