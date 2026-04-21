require "aws-sdk-sqs"
require "json"
require_relative "queue_adapter/sqs_adapter"

module FaleComChannel
  # Factory module for queue adapters.
  #
  # Usage:
  #   adapter = FaleComChannel::QueueAdapter.build(backend: :sqs, queue_name: "my-queue")
  #
  # Every adapter must implement:
  #   #consume(&handler) — long-polls and yields (body, receipt_handle, message_attributes)
  #   #ack(receipt_handle)   — acknowledges (deletes) a message
  #   #nack(receipt_handle)  — makes a message immediately visible again (visibility_timeout: 0)
  #   #enqueue(payload)      — sends a message (JSON-encodes the payload)
  #   #stop!                 — signals the consume loop to stop after current iteration
  module QueueAdapter
    # Builds and returns a queue adapter for the given backend.
    #
    # @param backend [Symbol] which backend to use (:sqs is the only supported value)
    # @param opts [Hash] passed through to the adapter constructor
    # @return [FaleComChannel::QueueAdapter::SqsAdapter]
    # @raise [ArgumentError] if the backend is not recognised
    def self.build(backend: :sqs, **opts)
      case backend
      when :sqs then SqsAdapter.new(**opts)
      else raise ArgumentError, "Unknown queue backend: #{backend.inspect}"
      end
    end
  end
end
