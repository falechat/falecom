require "rails_helper"

RSpec.describe Contacts::UpdateAttributes do
  let(:contact) { Contact.create!(name: "C", additional_attributes: {"plan" => "free"}) }

  it "merges attrs" do
    described_class.call(contact: contact, additional_attributes: {"plan" => "enterprise", "crm_url" => "https://x"})
    expect(contact.reload.additional_attributes).to eq("plan" => "enterprise", "crm_url" => "https://x")
  end

  it "removes keys passed as nil" do
    described_class.call(contact: contact, additional_attributes: {"plan" => nil})
    expect(contact.reload.additional_attributes).to eq({})
  end
end
