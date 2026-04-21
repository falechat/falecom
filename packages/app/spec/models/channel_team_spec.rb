require "rails_helper"

RSpec.describe ChannelTeam, type: :model do
  it "belongs to channel" do
    reflection = ChannelTeam.reflect_on_association(:channel)
    expect(reflection).not_to be_nil
    expect(reflection.macro).to eq(:belongs_to)
  end

  it "belongs to team" do
    reflection = ChannelTeam.reflect_on_association(:team)
    expect(reflection).not_to be_nil
    expect(reflection.macro).to eq(:belongs_to)
  end

  it "enforces uniqueness of (channel_id, team_id)" do
    channel = Channel.create!(channel_type: "whatsapp_cloud", identifier: "5511999999999", name: "Test Channel")
    team = Team.create!(name: "Sales")
    ChannelTeam.create!(channel: channel, team: team)
    expect {
      ChannelTeam.create!(channel: channel, team: team)
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
