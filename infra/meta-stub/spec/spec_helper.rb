ENV["RACK_ENV"] = "test"
ENV["WHATSAPP_APP_SECRET"] ||= "test-app-secret"
ENV["DEV_WEBHOOK_URL"] ||= "http://dev-webhook:4000"

require "rack/test"
require "webmock/rspec"
require_relative "../app"
require_relative "../lib/webhook_builder"
require_relative "../lib/dev_webhook_pusher"

WebMock.disable_net_connect!

RSpec.configure do |c|
  c.expect_with :rspec do |e|
    e.syntax = :expect
  end
end
