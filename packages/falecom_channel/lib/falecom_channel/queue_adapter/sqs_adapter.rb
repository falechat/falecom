require "concurrent"
require "json"

module FaleComChannel
  module QueueAdapter
    # Concrete SQS adapter that wraps `Aws::SQS::Client`.
    #
    # Constructor options:
    #   queue_name:        [String]  SQS queue name — required
    #   wait_time_seconds: [Integer] long-poll duration (default: 20)
    #   visibility_timeout:[Integer] how long a message is hidden while being processed (default: 30)
    #   client:            [Aws::SQS::Client, nil] optional client; one is built automatically if nil
    #
    # Thread-safety: #stop! is safe to call from any thread. The consume loop checks
    # the stop flag between iterations.
    class SqsAdapter
      def initialize(queue_name:, wait_time_seconds: 20, visibility_timeout: 30, client: nil)
        @queue_name = queue_name
        @wait_time_seconds = wait_time_seconds
        @visibility_timeout = visibility_timeout
        @client = client || Aws::SQS::Client.new
        @stop_flag = Concurrent::AtomicBoolean.new(false)
        @queue_url = nil
      end

      # Long-polls SQS in a loop, yielding (body, receipt_handle, message_attributes)
      # for each message. Loops until #stop! is called.
      #
      # @yield [String, String, Hash] body, receipt_handle, message_attributes
      def consume(&handler)
        @stop_flag.value = false

        loop do
          break if @stop_flag.true?

          response = @client.receive_message(
            queue_url: queue_url,
            max_number_of_messages: 1,
            wait_time_seconds: @wait_time_seconds,
            message_attribute_names: ["All"]
          )

          response.messages.each do |message|
            break if @stop_flag.true?

            attrs = message.message_attributes.transform_values { |v| v.string_value || v.binary_value }
            handler.call(message.body, message.receipt_handle, attrs)
          end

          break if @stop_flag.true?
        end
      end

      # Acknowledges a message by deleting it from the queue.
      #
      # @param receipt_handle [String]
      def ack(receipt_handle)
        @client.delete_message(
          queue_url: queue_url,
          receipt_handle: receipt_handle
        )
      end

      # Makes a message immediately visible again by setting visibility_timeout to 0.
      # This causes SQS to re-deliver the message to another consumer immediately.
      #
      # @param receipt_handle [String]
      def nack(receipt_handle)
        @client.change_message_visibility(
          queue_url: queue_url,
          receipt_handle: receipt_handle,
          visibility_timeout: 0
        )
      end

      # Sends a message to the queue with the payload JSON-encoded as the body.
      #
      # @param payload [Hash, Object] anything JSON-serializable
      def enqueue(payload)
        @client.send_message(
          queue_url: queue_url,
          message_body: JSON.generate(payload)
        )
      end

      # Signals the consume loop to stop after finishing the current iteration.
      def stop!
        @stop_flag.value = true
      end

      private

      # Lazily resolves the SQS queue URL from the queue name and caches it.
      def queue_url
        @queue_url ||= @client.get_queue_url(queue_name: @queue_name).queue_url
      end
    end
  end
end
