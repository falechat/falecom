require "spec_helper"
require "timeout"

# Minimal mock SQS adapter for Consumer tests.
# Yields one message then blocks until told to stop, or immediately if stop! was pre-called.
class MockSqsAdapter
  attr_reader :acked, :nacked

  def initialize(messages: [])
    @messages = messages
    @acked = []
    @nacked = []
    @stopped = false
  end

  def consume(&handler)
    @messages.each do |msg|
      break if @stopped

      handler.call(msg[:body], msg[:receipt_handle], msg[:attrs] || {})
    end
    # If not stopped yet, block until stopped
    sleep 0.01 until @stopped
  end

  def ack(receipt_handle)
    @acked << receipt_handle
  end

  def nack(receipt_handle)
    @nacked << receipt_handle
  end

  def enqueue(payload)
    # no-op for tests
  end

  def stop!
    @stopped = true
  end
end

# Test container that includes FaleComChannel::Consumer
class TestContainer
  include FaleComChannel::Consumer

  queue_name "test-queue"
  concurrency 1
end

# Test container with a custom handle that records calls
class RecordingContainer
  include FaleComChannel::Consumer

  queue_name "test-queue"
  concurrency 1

  attr_reader :handled

  def initialize
    super
    @handled = []
  end

  def handle(body, headers)
    @handled << {body: body, headers: headers}
  end
end

# Test container whose handle raises an error
class FailingContainer
  include FaleComChannel::Consumer

  queue_name "test-queue"
  concurrency 1

  def handle(body, headers)
    raise StandardError, "intentional failure"
  end
end

RSpec.describe FaleComChannel::Consumer do
  describe "class-level configuration" do
    it "defines queue_name and concurrency class setters" do
      expect(TestContainer).to respond_to(:queue_name)
      expect(TestContainer).to respond_to(:concurrency)
    end

    it "stores the queue_name set by the class macro" do
      expect(TestContainer.queue_name).to eq("test-queue")
    end

    it "stores the concurrency set by the class macro" do
      expect(TestContainer.concurrency).to eq(1)
    end

    it "default concurrency is 1 when not set" do
      klass = Class.new do
        include FaleComChannel::Consumer

        queue_name "q"
      end
      expect(klass.concurrency).to eq(1)
    end

    it "default queue_name reads from ENV['SQS_QUEUE_NAME'] when not set explicitly" do
      klass = Class.new { include FaleComChannel::Consumer }
      allow(ENV).to receive(:fetch).with("SQS_QUEUE_NAME", nil).and_return("env-queue")
      # Reading queue_name falls back to ENV
      expect(klass.instance_variable_get(:@queue_name)).to be_nil
    end
  end

  describe "#handle" do
    it "#handle raises NotImplementedError by default" do
      container = TestContainer.new
      expect { container.handle("body", {}) }.to raise_error(NotImplementedError)
    end
  end

  describe "#ingest_client" do
    it "#ingest_client memoizes a single IngestClient instance across calls" do
      stub_const("FaleComChannel::IngestClient", Class.new)
      fake_client = double("IngestClient")
      allow(FaleComChannel::IngestClient).to receive(:new).and_return(fake_client)

      container = TestContainer.new
      first = container.ingest_client
      second = container.ingest_client

      expect(FaleComChannel::IngestClient).to have_received(:new).once
      expect(first).to eq(second)
    end
  end

  describe "#start with mock adapter" do
    let(:mock_adapter) do
      MockSqsAdapter.new(messages: [
        {body: "hello", receipt_handle: "rh-1", attrs: {"X-Source" => "test"}}
      ])
    end

    let(:container) { RecordingContainer.new }

    before do
      allow(container).to receive(:build_adapter).and_return(mock_adapter)
    end

    it "successful #handle results in adapter.ack(receipt_handle)" do
      t = Thread.new { container.start(install_signal_traps: false) }
      # Give a bit of time for the message to be processed
      sleep 0.1
      mock_adapter.stop!
      t.join(3)

      expect(mock_adapter.acked).to include("rh-1")
      expect(mock_adapter.nacked).to be_empty
    end

    it "#start spawns the configured number of worker threads and processes messages" do
      t = Thread.new { container.start(install_signal_traps: false) }
      sleep 0.1
      mock_adapter.stop!
      t.join(3)

      expect(container.handled.length).to eq(1)
      expect(container.handled.first[:body]).to eq("hello")
    end
  end

  describe "#start with failing handle" do
    let(:mock_adapter) do
      MockSqsAdapter.new(messages: [
        {body: "boom", receipt_handle: "rh-fail", attrs: {}}
      ])
    end

    let(:container) { FailingContainer.new }

    before do
      allow(container).to receive(:build_adapter).and_return(mock_adapter)
      allow(FaleComChannel.logger).to receive(:error)
    end

    it "#handle raising StandardError results in adapter.nack(receipt_handle) and the error is logged" do
      t = Thread.new { container.start(install_signal_traps: false) }
      sleep 0.1
      mock_adapter.stop!
      t.join(3)

      expect(mock_adapter.nacked).to include("rh-fail")
      expect(mock_adapter.acked).to be_empty
      expect(FaleComChannel.logger).to have_received(:error).at_least(:once)
    end
  end

  describe "#shutdown!" do
    let(:blocking_adapter) { MockSqsAdapter.new(messages: []) }
    let(:container) { RecordingContainer.new }

    before do
      allow(container).to receive(:build_adapter).and_return(blocking_adapter)
    end

    it "#shutdown! causes #start to stop and return" do
      t = Thread.new { container.start(install_signal_traps: false) }
      sleep 0.05
      container.shutdown!
      finished = t.join(3)
      expect(finished).not_to be_nil
    end
  end

  describe "correlation ID per message" do
    let(:correlation_ids) { [] }

    let(:container) do
      ids = correlation_ids
      klass = Class.new do
        include FaleComChannel::Consumer

        queue_name "test-queue"
        concurrency 1

        define_method(:handle) do |body, headers|
          ids << FaleComChannel::Logging.current_correlation_id
        end
      end
      klass.new
    end

    let(:mock_adapter) do
      MockSqsAdapter.new(messages: [
        {body: "msg1", receipt_handle: "rh-a", attrs: {}},
        {body: "msg2", receipt_handle: "rh-b", attrs: {}}
      ])
    end

    before do
      allow(container).to receive(:build_adapter).and_return(mock_adapter)
    end

    it "each received message runs inside Logging.with_correlation_id with a fresh uuid" do
      t = Thread.new { container.start(install_signal_traps: false) }
      sleep 0.2
      mock_adapter.stop!
      t.join(3)

      expect(correlation_ids.length).to eq(2)
      correlation_ids.each do |cid|
        expect(cid).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
      end
      # Each message gets a unique ID
      expect(correlation_ids.uniq.length).to eq(correlation_ids.length)
    end
  end
end
