require "rails_helper"

RSpec.describe User, type: :model do
  let(:valid_attrs) { {name: "Test", email_address: "t@example.com", password: "password123", role: "agent"} }

  it "validates presence of name" do
    user = User.new(valid_attrs.merge(name: ""))
    expect(user).not_to be_valid
    expect(user.errors[:name]).not_to be_empty
  end

  it "validates presence of role" do
    user = User.new(valid_attrs.except(:role))
    expect(user).not_to be_valid
    expect(user.errors[:role]).not_to be_empty
  end

  it "validates presence of email_address" do
    user = User.new(valid_attrs.merge(email_address: ""))
    expect(user).not_to be_valid
    expect(user.errors[:email_address]).not_to be_empty
  end

  it "enforces uniqueness of email_address (case-insensitive)" do
    User.create!(valid_attrs)
    duplicate = User.new(valid_attrs.merge(email_address: "T@EXAMPLE.COM"))
    expect(duplicate).not_to be_valid
  end

  it "defines role enum with admin, supervisor, agent values" do
    expect(User.roles.keys).to eq(%w[admin supervisor agent])
  end

  it "defines availability enum with online, busy, offline values" do
    expect(User.availabilities.keys).to eq(%w[online busy offline])
  end

  it "defaults availability to offline" do
    user = User.create!(valid_attrs)
    expect(user.availability).to eq("offline")
  end

  it "has many team_members" do
    reflection = User.reflect_on_association(:team_members)
    expect(reflection).not_to be_nil
    expect(reflection.macro).to eq(:has_many)
  end

  it "has many teams through team_members" do
    reflection = User.reflect_on_association(:teams)
    expect(reflection).not_to be_nil
    expect(reflection.options[:through]).to eq(:team_members)
  end

  it "has many assigned_conversations with foreign_key assignee_id" do
    reflection = User.reflect_on_association(:assigned_conversations)
    expect(reflection.foreign_key.to_s).to eq("assignee_id")
    expect(reflection.class_name).to eq("Conversation")
  end

  it "rejects invalid role at the DB level via check constraint" do
    user = User.create!(valid_attrs)
    expect { user.update_column(:role, "bogus") }.to raise_error(ActiveRecord::StatementInvalid, /users_role_check/)
  end
end
