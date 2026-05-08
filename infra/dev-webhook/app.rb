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

          # Forward provider auth headers as SQS message attributes so the
          # consumer can verify them. Mirrors what API Gateway does in prod.
          attrs = {}
          %w[HTTP_X_HUB_SIGNATURE_256 HTTP_X_HUB_SIGNATURE HTTP_X_FALECOM_SIGNATURE HTTP_X_FALECOM_TIMESTAMP].each do |env_key|
            v = r.env[env_key]
            next if v.nil? || v.empty?
            header_name = env_key.sub(/\AHTTP_/, "").tr("_", "-").split("-").map(&:capitalize).join("-")
            attrs[header_name] = {data_type: "String", string_value: v}
          end

          DevWebhook.sqs_client.send_message(
            queue_url: queue_url,
            message_body: raw,
            message_attributes: attrs.empty? ? nil : attrs
          )

          response.status = 200
          response["Content-Type"] = "application/json"
          JSON.generate(status: "enqueued", queue: queue_name, bytes: raw.bytesize, attrs: attrs.keys)
        end
      end
    end
  end
end
