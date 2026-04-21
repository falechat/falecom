require "spec_helper"
require "json"

RSpec.describe FaleComChannel::QueueAdapter do
  describe ".build" do
    it "returns a SqsAdapter when backend: :sqs is given" do
      adapter = described_class.build(backend: :sqs, queue_name: "test-q", client: Aws::SQS::Client.new(stub_responses: true))
      expect(adapter).to be_a(FaleComChannel::QueueAdapter::SqsAdapter)
    end

    it "defaults to :sqs backend when backend is omitted" do
      adapter = described_class.build(queue_name: "test-q", client: Aws::SQS::Client.new(stub_responses: true))
      expect(adapter).to be_a(FaleComChannel::QueueAdapter::SqsAdapter)
    end

    it "raises ArgumentError for unknown backend" do
      expect {
        described_class.build(backend: :unknown_backend, queue_name: "test-q")
      }.to raise_error(ArgumentError, /Unknown queue backend/)
    end
  end
end

RSpec.describe FaleComChannel::QueueAdapter::SqsAdapter do
  let(:queue_name) { "test-queue" }
  let(:queue_url) { "https://sqs.us-east-1.amazonaws.com/123456789/test-queue" }

  let(:client) do
    c = Aws::SQS::Client.new(stub_responses: true)
    c.stub_responses(:get_queue_url, queue_url: queue_url)
    c
  end

  subject(:adapter) { described_class.new(queue_name: queue_name, client: client) }

  describe "#queue_url (lazy resolution and caching)" do
    it "resolves queue_url from queue_name on first call and caches it" do
      # Trigger queue_url resolution via ack (any method that uses queue_url)
      client.stub_responses(:delete_message, {})
      adapter.ack("handle-1")
      adapter.ack("handle-2")

      get_url_calls = client.api_requests.select { |r| r[:operation_name] == :get_queue_url }
      expect(get_url_calls.count).to eq(1)
    end
  end

  describe "#consume" do
    it "yields (body, receipt_handle, message_attributes) for each received message" do
      client.stub_responses(:receive_message, {
        messages: [
          {
            body: '{"hello":"world"}',
            receipt_handle: "rh-abc",
            message_attributes: {"X-Channel" => {string_value: "whatsapp", data_type: "String"}}
          }
        ]
      })

      yielded = []
      # consume loops forever — we stop it after one yield
      adapter_thread = Thread.new do
        adapter.consume do |body, receipt_handle, message_attributes|
          yielded << [body, receipt_handle, message_attributes]
          adapter.stop!
        end
      end
      adapter_thread.join(5)

      expect(yielded.length).to eq(1)
      body, receipt_handle, message_attributes = yielded.first
      expect(body).to eq('{"hello":"world"}')
      expect(receipt_handle).to eq("rh-abc")
      expect(message_attributes).to be_a(Hash)
    end

    it "stops looping when stop! is called" do
      call_count = 0
      client.stub_responses(:receive_message, {
        messages: [
          {body: "msg", receipt_handle: "rh-1", message_attributes: {}}
        ]
      })

      t = Thread.new do
        adapter.consume do |_body, _rh, _attrs|
          call_count += 1
          adapter.stop!
        end
      end

      finished = t.join(5)
      expect(finished).not_to be_nil
      expect(call_count).to be >= 1
    end

    it "continues polling even when receive_message returns no messages" do
      client.stub_responses(:receive_message, [
        {messages: []},
        {messages: []},
        {messages: [{body: "hit", receipt_handle: "rh-hit", message_attributes: {}}]}
      ])

      yielded_bodies = []
      t = Thread.new do
        adapter.consume do |body, _rh, _attrs|
          yielded_bodies << body
          adapter.stop!
        end
      end

      t.join(5)
      expect(yielded_bodies).to eq(["hit"])
    end
  end

  describe "#ack" do
    it "calls DeleteMessage with the receipt handle" do
      client.stub_responses(:delete_message, {})
      adapter.ack("receipt-handle-123")

      delete_calls = client.api_requests.select { |r| r[:operation_name] == :delete_message }
      expect(delete_calls.count).to eq(1)
      expect(delete_calls.first[:params][:receipt_handle]).to eq("receipt-handle-123")
    end
  end

  describe "#nack" do
    it "calls ChangeMessageVisibility with visibility_timeout 0" do
      client.stub_responses(:change_message_visibility, {})
      adapter.nack("receipt-handle-456")

      change_calls = client.api_requests.select { |r| r[:operation_name] == :change_message_visibility }
      expect(change_calls.count).to eq(1)
      expect(change_calls.first[:params][:receipt_handle]).to eq("receipt-handle-456")
      expect(change_calls.first[:params][:visibility_timeout]).to eq(0)
    end
  end

  describe "#enqueue" do
    it "calls SendMessage with the JSON-encoded payload" do
      client.stub_responses(:send_message, message_id: "msg-id-1", md5_of_message_body: "abc123")
      payload = {type: "inbound_message", channel: {type: "whatsapp_cloud"}}
      adapter.enqueue(payload)

      send_calls = client.api_requests.select { |r| r[:operation_name] == :send_message }
      expect(send_calls.count).to eq(1)
      sent_body = send_calls.first[:params][:message_body]
      expect(JSON.parse(sent_body)).to eq(JSON.parse(payload.to_json))
    end
  end
end
