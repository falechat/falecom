module Flows
  class MenuFormatter
    def self.call(content)
      header = content["text"].to_s
      options = (content["options"] || []).map { |o| "#{o["key"]} - #{o["label"]}" }.join("\n")
      "#{header}\n\n#{options}"
    end
  end
end
