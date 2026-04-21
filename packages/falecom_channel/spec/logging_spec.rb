require "spec_helper"
require "stringio"
require "json"

RSpec.describe "FaleComChannel::Logging" do
  # Helper: build a logger that writes to a StringIO using the same
  # JsonFormatter as the default logger, so we can inspect output.
  def logger_with_io(io)
    log = Logger.new(io)
    log.formatter = FaleComChannel::Logging::JsonFormatter.new
    log
  end

  around(:each) do |example|
    original_logger = FaleComChannel.logger
    example.run
    FaleComChannel.logger = original_logger
  end

  # Ensure correlation ID state is cleaned up between examples.
  # We wrap every example in a with_correlation_id block so after the spec
  # any mutation the example made to the thread-local is unwound automatically.
  around(:each) do |example|
    FaleComChannel::Logging.with_correlation_id(nil) { example.run }
  end

  describe "FaleComChannel.logger" do
    it "FaleComChannel.logger emits one JSON line per call to stdout" do
      io = StringIO.new
      FaleComChannel.logger = logger_with_io(io)

      FaleComChannel.logger.info("hello")

      lines = io.string.lines.reject(&:empty?)
      expect(lines.length).to eq(1)
      parsed = JSON.parse(lines.first)
      expect(parsed).to be_a(Hash)
    end

    it "FaleComChannel.logger.info(event: \"x\", foo: 1) includes event and foo keys in the JSON" do
      io = StringIO.new
      FaleComChannel.logger = logger_with_io(io)

      FaleComChannel.logger.info(event: "x", foo: 1)

      parsed = JSON.parse(io.string.lines.first)
      expect(parsed["event"]).to eq("x")
      expect(parsed["foo"]).to eq(1)
    end

    it "FaleComChannel.logger.info(\"plain string\") produces {\"message\":\"plain string\", ...}" do
      io = StringIO.new
      FaleComChannel.logger = logger_with_io(io)

      FaleComChannel.logger.info("plain string")

      parsed = JSON.parse(io.string.lines.first)
      expect(parsed["message"]).to eq("plain string")
    end
  end

  describe "FaleComChannel::Logging.with_correlation_id" do
    it "FaleComChannel::Logging.with_correlation_id sets current_correlation_id within the block" do
      FaleComChannel::Logging.with_correlation_id("abc-123") do
        expect(FaleComChannel::Logging.current_correlation_id).to eq("abc-123")
      end
    end

    it "FaleComChannel::Logging.current_correlation_id returns nil outside a with_correlation_id block" do
      # No block active — correlation ID must be nil
      expect(FaleComChannel::Logging.current_correlation_id).to be_nil
    end

    it "FaleComChannel::Logging.with_correlation_id restores the previous value on normal exit" do
      FaleComChannel::Logging.with_correlation_id("outer") do
        FaleComChannel::Logging.with_correlation_id("inner") do
          # inside inner
        end
        # back in outer
        expect(FaleComChannel::Logging.current_correlation_id).to eq("outer")
      end
      expect(FaleComChannel::Logging.current_correlation_id).to be_nil
    end

    it "FaleComChannel::Logging.with_correlation_id restores the previous value even when the block raises" do
      FaleComChannel::Logging.with_correlation_id("pre-raise") do
        expect {
          FaleComChannel::Logging.with_correlation_id("during-raise") do
            raise "boom"
          end
        }.to raise_error("boom")

        # Restored to the outer value
        expect(FaleComChannel::Logging.current_correlation_id).to eq("pre-raise")
      end
    end

    it "FaleComChannel::Logging.with_correlation_id supports nested blocks" do
      FaleComChannel::Logging.with_correlation_id("A") do
        expect(FaleComChannel::Logging.current_correlation_id).to eq("A")
        FaleComChannel::Logging.with_correlation_id("B") do
          expect(FaleComChannel::Logging.current_correlation_id).to eq("B")
        end
        expect(FaleComChannel::Logging.current_correlation_id).to eq("A")
      end
    end

    it "FaleComChannel::Logging.with_correlation_id is thread-local (one thread's value does not leak to another)" do
      main_id = "main-thread-id"
      other_id = nil
      Queue.new
      done = Queue.new

      FaleComChannel::Logging.with_correlation_id(main_id) do
        thread = Thread.new do
          # Other thread should see nil unless it sets its own
          other_id = FaleComChannel::Logging.current_correlation_id
          done.push(:done)
        end
        done.pop
        thread.join

        expect(other_id).to be_nil
        expect(FaleComChannel::Logging.current_correlation_id).to eq(main_id)
      end
    end
  end

  describe "logger output and correlation_id" do
    it "logger output includes correlation_id when inside a with_correlation_id block" do
      io = StringIO.new
      FaleComChannel.logger = logger_with_io(io)

      FaleComChannel::Logging.with_correlation_id("req-xyz") do
        FaleComChannel.logger.info("test message")
      end

      parsed = JSON.parse(io.string.lines.first)
      expect(parsed["correlation_id"]).to eq("req-xyz")
    end

    it "logger output omits correlation_id when no block is active" do
      io = StringIO.new
      FaleComChannel.logger = logger_with_io(io)

      FaleComChannel.logger.info("no correlation")

      parsed = JSON.parse(io.string.lines.first)
      expect(parsed).not_to have_key("correlation_id")
    end
  end

  describe "FaleComChannel.logger=" do
    it "FaleComChannel.logger = custom preserves the JSON structure if caller wires a compatible formatter" do
      io = StringIO.new
      custom_logger = logger_with_io(io)
      FaleComChannel.logger = custom_logger

      FaleComChannel.logger.info(event: "custom_test", value: 42)

      parsed = JSON.parse(io.string.lines.first)
      expect(parsed["event"]).to eq("custom_test")
      expect(parsed["value"]).to eq(42)
      expect(parsed).to have_key("level")
      expect(parsed).to have_key("time")
    end
  end
end
