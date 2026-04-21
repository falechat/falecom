require "rails_helper"

RSpec.describe Team, type: :model do
  it "validates presence of name" do
    team = Team.new(name: "")
    expect(team).not_to be_valid
    expect(team.errors[:name]).not_to be_empty
  end

  it "has many team_members" do
    reflection = Team.reflect_on_association(:team_members)
    expect(reflection).not_to be_nil
    expect(reflection.macro).to eq(:has_many)
  end

  it "has many users through team_members" do
    reflection = Team.reflect_on_association(:users)
    expect(reflection).not_to be_nil
    expect(reflection.options[:through]).to eq(:team_members)
  end

  it "has many channel_teams" do
    reflection = Team.reflect_on_association(:channel_teams)
    expect(reflection).not_to be_nil
    expect(reflection.macro).to eq(:has_many)
  end

  it "has many channels through channel_teams" do
    reflection = Team.reflect_on_association(:channels)
    expect(reflection).not_to be_nil
    expect(reflection.options[:through]).to eq(:channel_teams)
  end

  it "has many conversations with dependent: :restrict_with_error" do
    reflection = Team.reflect_on_association(:conversations)
    expect(reflection).not_to be_nil
    expect(reflection.macro).to eq(:has_many)
    expect(reflection.options[:dependent]).to eq(:restrict_with_error)
  end
end
