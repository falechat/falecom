ENV["AWS_REGION"] ||= "us-east-1"
ENV["AWS_ACCESS_KEY_ID"] ||= "test"
ENV["AWS_SECRET_ACCESS_KEY"] ||= "test"

require "rspec"
require "rack/test"
require_relative "../app"

RSpec.configure do |c|
  c.filter_run_when_matching :focus
  c.expose_dsl_globally = true
  c.before(:each) { DevWebhook.reset_client! }
end
