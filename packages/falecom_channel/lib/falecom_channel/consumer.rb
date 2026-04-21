require "concurrent"
require "securerandom"

module FaleComChannel
  # Mixin module included by channel container classes to get a polling loop.
  #
  # Usage:
  #   class WhatsappCloudContainer
  #     include FaleComChannel::Consumer
  #
  #     queue_name ENV.fetch("SQS_QUEUE_NAME")
  #     concurrency Integer(ENV.fetch("CONCURRENCY", 1))
  #
  #     def handle(body, headers)
  #       # parse provider payload, POST via ingest_client
  #     end
  #   end
  #
  # Call `#start` to begin the polling loop. It blocks until shutdown.
  # Call `#shutdown!` or send SIGTERM/SIGINT to stop gracefully.
  module Consumer
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      # Sets or retrieves the SQS queue name for this container class.
      # Falls back to ENV["SQS_QUEUE_NAME"] if never set.
      def queue_name(name = nil)
        if name.nil?
          @queue_name || ENV.fetch("SQS_QUEUE_NAME", nil)
        else
          @queue_name = name
        end
      end

      # Sets or retrieves the worker concurrency for this container class.
      # Default is 1.
      def concurrency(n = nil)
        if n.nil?
          @concurrency || 1
        else
          @concurrency = n
        end
      end
    end

    # Builds and returns the queue adapter.
    # Exposed as a protected method so specs can stub it.
    #
    # @return [FaleComChannel::QueueAdapter::SqsAdapter]
    def build_adapter
      FaleComChannel::QueueAdapter.build(
        backend: :sqs,
        queue_name: self.class.queue_name
      )
    end

    # Starts the polling loop. Blocks until shutdown.
    #
    # Signal handlers for TERM and INT are installed unless
    # `install_signal_traps:` is false (useful in tests).
    #
    # @param install_signal_traps [Boolean] whether to install SIGTERM/SIGINT handlers (default: true)
    def start(install_signal_traps: true)
      @stop_flag = Concurrent::AtomicBoolean.new(false)
      @adapter = build_adapter

      if install_signal_traps
        Signal.trap("TERM") { shutdown_and_stop_adapter(@adapter) }
        Signal.trap("INT") { shutdown_and_stop_adapter(@adapter) }
      end

      workers = self.class.concurrency.times.map do
        Thread.new { worker_loop(@adapter) }
      end

      # Block until all workers finish
      workers.each(&:join)
    end

    # Signals all worker threads (and the adapter) to stop.
    def shutdown!
      @stop_flag&.value = true
      @adapter&.stop!
    end

    # Container-specific message handler.
    # Subclasses must override this method.
    #
    # @param body [String] raw SQS message body
    # @param headers [Hash] SQS message attributes (string_value extracted)
    # @raise [NotImplementedError] when not overridden in subclass
    def handle(body, headers)
      raise NotImplementedError, "#{self.class.name}#handle is not implemented"
    end

    # Returns (and memoizes) the ingest client. Defaults to an IngestClient
    # built from ENV vars; channel containers override this method if they
    # need to inject a custom client or pass additional options.
    #
    # @return [FaleComChannel::IngestClient]
    def ingest_client
      @ingest_client ||= FaleComChannel::IngestClient.new(
        api_url: ENV.fetch("FALECOM_API_URL"),
        secret: ENV.fetch("FALECOM_INGEST_HMAC_SECRET")
      )
    end

    protected :build_adapter

    private

    # Main loop for a single worker thread.
    def worker_loop(adapter)
      adapter.consume do |body, receipt_handle, message_attributes|
        break if @stop_flag.true?

        correlation_id = SecureRandom.uuid
        FaleComChannel::Logging.with_correlation_id(correlation_id) do
          handle(body, message_attributes)
          adapter.ack(receipt_handle)
        rescue => e
          FaleComChannel.logger.error(
            event: "handle_failed",
            error: e.message,
            error_class: e.class.name
          )
          adapter.nack(receipt_handle)
        end
      end
    end

    def shutdown_and_stop_adapter(adapter)
      @stop_flag&.value = true
      adapter.stop!
    end
  end
end
