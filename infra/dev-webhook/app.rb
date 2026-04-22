require "roda"
require "aws-sdk-sqs"
require "json"

# Dev-only helper that mimics AWS API Gateway's direct-to-SQS integration.
# Receives a provider webhook POST and enqueues the raw body to the matching
# LocalStack SQS queue. No auth, no DB, no HMAC.
module DevWebhook
  QUEUE_BY_CHANNEL = {
    "whatsapp-cloud" => "sqs-whatsapp-cloud",
    "zapi" => "sqs-zapi"
  }.freeze

  def self.app
    App
  end

  def self.sqs_client
    @sqs_client ||= Aws::SQS::Client.new(region: ENV.fetch("AWS_REGION", "us-east-1"))
  end

  def self.reset_client!
    @sqs_client = nil
  end

  class App < Roda
    route do |r|
      r.on "webhooks", String do |channel_type|
        queue_name = QUEUE_BY_CHANNEL[channel_type]
        unless queue_name
          response.status = 404
          response["Content-Type"] = "application/json"
          r.halt([404, {"Content-Type" => "application/json"}, [JSON.generate(error: "unknown_channel_type")]])
        end

        r.post do
          raw = r.body.read
          queue_url = DevWebhook.sqs_client.get_queue_url(queue_name: queue_name).queue_url
          DevWebhook.sqs_client.send_message(queue_url: queue_url, message_body: raw)
          response.status = 200
          response["Content-Type"] = "application/json"
          JSON.generate(status: "enqueued", queue: queue_name, bytes: raw.bytesize)
        end
      end
    end
  end
end
