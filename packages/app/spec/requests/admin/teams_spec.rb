require "rails_helper"

RSpec.describe "Admin::Teams", type: :request do
  def make_user(role: "agent")
    User.create!(name: "U-#{SecureRandom.hex(3)}", email_address: "u-#{SecureRandom.hex(4)}@x.test",
      password: "password", role: role, availability: "online")
  end

  def make_channel
    Channel.create!(channel_type: "whatsapp_cloud", identifier: "wa-#{SecureRandom.hex(3)}", name: "WA")
  end

  def sign_in(user)
    post session_path, params: {email_address: user.email_address, password: "password"}
  end

  let(:admin) { make_user(role: "admin") }
  before { sign_in(admin) }

  it "creates a team with channel + member assignments" do
    ch = make_channel
    u = make_user
    post admin_teams_path, params: {team: {name: "Sales", user_ids: [u.id], channel_ids: [ch.id]}}
    team = Team.find_by(name: "Sales")
    expect(team.users).to include(u)
    expect(team.channels).to include(ch)
  end

  it "updates membership idempotently" do
    team = Team.create!(name: "T-#{SecureRandom.hex(3)}")
    u1 = make_user
    u2 = make_user
    TeamMember.create!(user: u1, team: team)
    patch admin_team_path(team), params: {team: {name: team.name, user_ids: [u2.id]}}
    expect(team.reload.users).to contain_exactly(u2)
  end
end
