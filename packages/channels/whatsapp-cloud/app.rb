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
      raise NotImplementedError, "wired in Task 7"
    end
  end
end

WhatsappCloud::Container.new.start if __FILE__ == $PROGRAM_NAME
