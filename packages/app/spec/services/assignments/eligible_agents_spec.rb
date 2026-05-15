require "rails_helper"

RSpec.describe Assignments::EligibleAgents do
  def make_user(role: "agent", availability: "online")
    User.create!(
      name: "U-#{SecureRandom.hex(3)}",
      email_address: "u-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      role: role,
      availability: availability
    )
  end

  let(:team) { Team.create!(name: "T-#{SecureRandom.hex(3)}") }
  let!(:on) { make_user(availability: "online").tap { |u| TeamMember.create!(user: u, team: team) } }
  let!(:busy) { make_user(availability: "busy").tap { |u| TeamMember.create!(user: u, team: team) } }
  let!(:off) { make_user(availability: "offline").tap { |u| TeamMember.create!(user: u, team: team) } }
  let!(:other) { make_user(availability: "online") } # not on team

  it "returns only online members of the team" do
    expect(described_class.call(team)).to contain_exactly(on)
  end
end
