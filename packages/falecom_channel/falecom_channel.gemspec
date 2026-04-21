require_relative "lib/falecom_channel/version"

Gem::Specification.new do |spec|
  spec.name = "falecom_channel"
  spec.version = FaleComChannel::VERSION
  spec.authors = ["FaleCom"]
  spec.summary = "Shared infrastructure for FaleCom channel containers."
  spec.description = "Common Ingestion Payload schema, SQS consumer loop, HMAC-signed HTTP clients, and Roda /send server base for FaleCom channel containers."
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir["lib/**/*.rb", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "aws-sdk-sqs", "~> 1.80"
  spec.add_dependency "concurrent-ruby", "~> 1.3"
  spec.add_dependency "dry-struct", "~> 1.6"
  spec.add_dependency "dry-validation", "~> 1.10"
  spec.add_dependency "faraday", "~> 2.9"
  spec.add_dependency "faraday-retry", "~> 2.2"
  spec.add_dependency "roda", "~> 3.86"
end
