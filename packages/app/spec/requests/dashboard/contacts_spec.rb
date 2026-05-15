require "rails_helper"

RSpec.describe "Dashboard::Contacts", type: :request do
  def make_user(role: "agent")
    User.create!(name: "U-#{SecureRandom.hex(3)}", email_address: "u-#{SecureRandom.hex(4)}@x.test",
      password: "password", role: role, availability: "online")
  end

  def sign_in(user)
    post session_path, params: {email_address: user.email_address, password: "password"}
  end

  let(:agent) { make_user }
  before { sign_in(agent) }

  it "creates a contact" do
    expect {
      post dashboard_contacts_path, params: {contact: {name: "Maria", phone_number: "+55"}}
    }.to change(Contact, :count).by(1)
  end

  it "updates attributes" do
    c = Contact.create!(name: "C")
    patch dashboard_contact_path(c), params: {contact: {name: c.name, additional_attributes: {"plan" => "enterprise"}}}
    expect(c.reload.additional_attributes).to eq("plan" => "enterprise")
  end
end
