require "json"
require "logger"
require "time"

module FaleComChannel
  CORRELATION_ID_KEY = :falecom_channel_correlation_id
  private_constant :CORRELATION_ID_KEY

  class << self
    def logger
      @logger ||= build_default_logger
    end

    attr_writer :logger

    private

    def build_default_logger
      log = Logger.new($stdout)
      log.formatter = Logging::JsonFormatter.new
      log
    end
  end

  module Logging
    # Sets a correlation ID for the duration of the block.
    # Nested calls are supported — the previous value is restored on exit
    # (including when the block raises).
    #
    # @param id [String] correlation ID to set
    # @yield block to execute with the correlation ID set
    def self.with_correlation_id(id)
      previous = Thread.current[CORRELATION_ID_KEY]
      Thread.current[CORRELATION_ID_KEY] = id
      yield
    ensure
      Thread.current[CORRELATION_ID_KEY] = previous
    end

    # Returns the current thread's correlation ID, or nil if none is set.
    #
    # @return [String, nil]
    def self.current_correlation_id
      Thread.current[CORRELATION_ID_KEY]
    end

    # Custom Logger::Formatter that writes one JSON line per log message to stdout.
    # Accepts either a String message or a Hash of keyword fields.
    class JsonFormatter
      def call(severity, time, _progname, msg)
        entry = base_entry(severity, time)
        merge_message(entry, msg)
        "#{entry.to_json}\n"
      end

      private

      def base_entry(severity, time)
        entry = {
          "level" => severity.downcase,
          "time" => time.utc.iso8601
        }
        cid = Thread.current[CORRELATION_ID_KEY]
        entry["correlation_id"] = cid unless cid.nil?
        entry
      end

      def merge_message(entry, msg)
        case msg
        when Hash
          msg.each { |k, v| entry[k.to_s] = v }
        else
          entry["message"] = msg.to_s
        end
      end
    end
  end
end
