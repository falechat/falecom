module DispatchClientStub
  def stub_dispatch_client(response: {"external_id" => "ext-1"}, raise_error: nil)
    fake = instance_double(FaleComChannel::DispatchClient)
    if raise_error
      allow(fake).to receive(:send_message).and_raise(raise_error)
    else
      allow(fake).to receive(:send_message).and_return(response)
    end
    allow(FaleComChannel::DispatchClient).to receive(:new).and_return(fake)
    fake
  end
end

RSpec.configure { |c| c.include DispatchClientStub }
