class Team < ApplicationRecord
  validates :name, presence: true

  has_many :team_members, dependent: :destroy
  has_many :users, through: :team_members
  has_many :channel_teams, dependent: :destroy
  has_many :channels, through: :channel_teams
  has_many :conversations, dependent: :restrict_with_error
end
