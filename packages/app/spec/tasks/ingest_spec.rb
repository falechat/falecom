require "rails_helper"
require "rake"

RSpec.describe "ingest:mock rake task" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("ingest:mock")
  end

  before do
    Rake::Task["ingest:mock"].reenable
    Channel.create!(channel_type: "whatsapp_cloud", identifier: "+5511999999999", name: "WhatsApp Sales")
  end

  it "creates a Message via Ingestion::ProcessMessage when run with default args" do
    expect {
      silence_stream($stdout) { Rake::Task["ingest:mock"].invoke }
    }.to change { Message.count }.by(1)
  end

  it "passes the provided content through to the Message" do
    silence_stream($stdout) { Rake::Task["ingest:mock"].invoke("hello from rake") }
    expect(Message.last.content).to eq("hello from rake")
  end

  # Rails 8 doesn't ship the old `silence_stream` helper; polyfill inline.
  def silence_stream(stream)
    old = stream.dup
    stream.reopen(IO::NULL)
    yield
  ensure
    stream.reopen(old)
  end
end
