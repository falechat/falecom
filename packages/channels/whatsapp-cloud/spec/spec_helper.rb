ENV["AWS_REGION"] ||= "us-east-1"
ENV["AWS_ACCESS_KEY_ID"] ||= "test"
ENV["AWS_SECRET_ACCESS_KEY"] ||= "test"
ENV["FALECOM_API_URL"] ||= "http://rails.test"
ENV["WHATSAPP_APP_SECRET"] ||= "test-app-secret"
ENV["WHATSAPP_ACCESS_TOKEN"] ||= "test-access-token"

require "rspec"
require "rack/test"
require "webmock/rspec"
WebMock.disable_net_connect!

require "falecom_channel"
require_relative "../lib/parser"
require_relative "../lib/signature_verifier"
require_relative "../lib/sender"
require_relative "../lib/send_server"
require_relative "support/fixtures"

RSpec.configure do |c|
  c.filter_run_when_matching :focus
  c.expose_dsl_globally = true
end
