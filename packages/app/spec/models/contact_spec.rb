require "rails_helper"

RSpec.describe Contact, type: :model do
  it "has many contact_channels" do
    reflection = Contact.reflect_on_association(:contact_channels)
    expect(reflection).not_to be_nil
    expect(reflection.macro).to eq(:has_many)
  end

  it "has many channels through contact_channels" do
    reflection = Contact.reflect_on_association(:channels)
    expect(reflection).not_to be_nil
    expect(reflection.options[:through]).to eq(:contact_channels)
  end

  it "has many conversations" do
    reflection = Contact.reflect_on_association(:conversations)
    expect(reflection).not_to be_nil
    expect(reflection.macro).to eq(:has_many)
  end

  it "allows blank name/email/phone_number/identifier" do
    contact = Contact.new(name: nil, email: nil, phone_number: nil, identifier: nil)
    expect(contact).to be_valid
  end
end
