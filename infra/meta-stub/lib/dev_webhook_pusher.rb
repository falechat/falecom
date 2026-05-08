require "net/http"
require "openssl"
require "json"
require "uri"

module MetaStub
  # POSTs a Meta-shaped webhook to dev-webhook with a valid X-Hub-Signature-256
  # so the WhatsApp container's SignatureVerifier accepts it.
  class DevWebhookPusher
    def initialize(dev_webhook_url: ENV.fetch("DEV_WEBHOOK_URL", "http://dev-webhook:4000"),
      app_secret: ENV.fetch("WHATSAPP_APP_SECRET", "dev-app-secret"),
      channel_type: "whatsapp-cloud")
      @url = URI.join(dev_webhook_url + "/", "webhooks/#{channel_type}")
      @app_secret = app_secret
    end

    def push(payload_hash)
      body = JSON.generate(payload_hash)
      sig = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", @app_secret, body)

      Net::HTTP.start(@url.host, @url.port, use_ssl: @url.scheme == "https") do |http|
        req = Net::HTTP::Post.new(@url.request_uri)
        req["Content-Type"] = "application/json"
        req["X-Hub-Signature-256"] = sig
        req.body = body
        http.request(req)
      end
    end
  end
end
