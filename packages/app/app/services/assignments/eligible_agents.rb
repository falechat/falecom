module Assignments
  class EligibleAgents
    def self.call(team)
      User.joins(:team_members)
        .where(team_members: {team_id: team.id})
        .where(availability: "online")
    end
  end
end
