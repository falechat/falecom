class ChannelTeam < ApplicationRecord
  belongs_to :channel
  belongs_to :team
end
