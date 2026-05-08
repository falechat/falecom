require "rails_helper"

RSpec.describe Dispatch::ContainerUrlResolver do
  it "resolves CHANNEL_WHATSAPP_CLOUD_URL for whatsapp_cloud" do
    stub_const("ENV", ENV.to_h.merge("CHANNEL_WHATSAPP_CLOUD_URL" => "http://wa:9292"))
    expect(described_class.call("whatsapp_cloud")).to eq("http://wa:9292")
  end

  it "raises KeyError when env var is missing" do
    env = ENV.to_h.except("CHANNEL_WHATSAPP_CLOUD_URL")
    stub_const("ENV", env)
    expect { described_class.call("whatsapp_cloud") }.to raise_error(KeyError)
  end

  it "uppercases the channel_type for env lookup" do
    stub_const("ENV", ENV.to_h.merge("CHANNEL_Z_API_URL" => "http://z:9293"))
    expect(described_class.call("z_api")).to eq("http://z:9293")
  end
end
