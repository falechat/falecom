require "rails_helper"

RSpec.describe "Admin::Users", type: :request do
  def make_user(role: "agent")
    User.create!(name: "U-#{SecureRandom.hex(3)}", email_address: "u-#{SecureRandom.hex(4)}@x.test",
      password: "password", role: role, availability: "online")
  end

  def sign_in(user)
    post session_path, params: {email_address: user.email_address, password: "password"}
  end

  let(:admin) { make_user(role: "admin") }
  before { sign_in(admin) }

  it "creates a user with role + team membership" do
    team = Team.create!(name: "T-#{SecureRandom.hex(3)}")
    post admin_users_path, params: {user: {name: "Maria", email_address: "m-#{SecureRandom.hex(3)}@x.com", password: "abcdef12", role: "agent", availability: "offline", team_ids: [team.id]}}
    u = User.find_by(name: "Maria")
    expect(u.role).to eq("agent")
    expect(u.teams).to include(team)
  end

  it "PATCH updates without requiring password" do
    u = make_user
    patch admin_user_path(u), params: {user: {name: "New name"}}
    expect(u.reload.name).to eq("New name")
  end
end
