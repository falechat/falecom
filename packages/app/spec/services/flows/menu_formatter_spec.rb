require "rails_helper"

RSpec.describe Flows::MenuFormatter do
  it "formats text + numbered options" do
    content = {
      "text" => "Como posso ajudar?",
      "options" => [
        {"key" => "1", "label" => "Vendas"},
        {"key" => "2", "label" => "Suporte"}
      ]
    }
    out = described_class.call(content)
    expect(out).to eq("Como posso ajudar?\n\n1 - Vendas\n2 - Suporte")
  end
end
