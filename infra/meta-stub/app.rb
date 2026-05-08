require "roda"
require "json"
require "securerandom"

class MetaStub < Roda
  plugin :json

  route do |r|
    r.get "health" do
      {"status" => "ok"}
    end

    r.on "v21.0", String, "messages" do |_phone_number_id|
      r.post do
        {messages: [{id: "wamid.test-#{SecureRandom.hex(4)}"}]}
      end
    end
  end
end
