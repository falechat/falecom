module Dispatch
  class ContainerUrlResolver
    def self.call(channel_type)
      ENV.fetch("CHANNEL_#{channel_type.upcase}_URL")
    end
  end
end
