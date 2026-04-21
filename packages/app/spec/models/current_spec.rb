require "rails_helper"

RSpec.describe Current do
  before { Current.reset }
  after { Current.reset }

  it "exposes a user attribute that can be set and read" do
    user = User.new(email_address: "x@y.com", name: "X", role: "agent")
    Current.user = user
    expect(Current.user).to be_a(User)
    expect(Current.user).to eq(user)
  end

  it "preserves the existing session delegation" do
    user = User.create!(name: "Bob", email_address: "bob@example.com", password: "password123", role: "agent")
    session = Session.create!(user: user)
    Current.session = session
    expect(Current.user).to eq(user)
  end

  it "allows setting Current.user directly without a session" do
    user = User.new(email_address: "direct@example.com", name: "Direct", role: "agent")
    Current.user = user
    expect(Current.user).to eq(user)
    expect(Current.session).to be_nil
  end

  it "resets user and session on Current.reset" do
    user = User.new(email_address: "reset@example.com", name: "Reset", role: "agent")
    Current.user = user
    Current.reset
    expect(Current.user).to be_nil
    expect(Current.session).to be_nil
  end
end
