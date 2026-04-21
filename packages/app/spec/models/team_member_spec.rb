require "rails_helper"

RSpec.describe TeamMember, type: :model do
  it "belongs to team" do
    reflection = TeamMember.reflect_on_association(:team)
    expect(reflection).not_to be_nil
    expect(reflection.macro).to eq(:belongs_to)
  end

  it "belongs to user" do
    reflection = TeamMember.reflect_on_association(:user)
    expect(reflection).not_to be_nil
    expect(reflection.macro).to eq(:belongs_to)
  end

  it "enforces uniqueness of (team_id, user_id)" do
    user = User.create!(name: "Alice", email_address: "alice@example.com", password: "password123", role: "agent")
    team = Team.create!(name: "Support")
    TeamMember.create!(team: team, user: user)
    expect {
      TeamMember.create!(team: team, user: user)
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
