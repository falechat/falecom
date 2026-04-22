require "aws-sdk-sqs"

namespace :sqs do
  desc "Create dev SQS queues in LocalStack (idempotent). Uses AWS_ENDPOINT_URL_SQS."
  task :ensure_queues do
    queues = %w[sqs-whatsapp-cloud sqs-zapi]
    client = Aws::SQS::Client.new(region: ENV.fetch("AWS_REGION", "us-east-1"))
    queues.each do |name|
      url = client.create_queue(queue_name: name).queue_url
      puts "SQS queue ready: #{name} → #{url}"
    rescue Aws::SQS::Errors::ServiceError => e
      warn "SQS queue setup failed for #{name}: #{e.message}"
    end
  end
end
