class TimelineEventComponent < ViewComponent::Base
  def initialize(event:)
    @event = event
  end

  def label
    case @event.name
    when "conversations:assigned"
      who = User.find_by(id: @event.payload["assignee_id"])&.name || "agent"
      "Assigned to #{who}"
    when "conversations:transferred"
      from = User.find_by(id: @event.payload["from_user_id"])&.name
      to = User.find_by(id: @event.payload["to_user_id"])&.name
      team = Team.find_by(id: @event.payload["to_team_id"])&.name
      to_label = [to, team].compact.join(" / ").presence || "queued"
      "Transferred #{"from #{from} " if from}to #{to_label}"
    when "conversations:resolved"
      "Resolved"
    when "flows:handoff"
      team = Team.find_by(id: @event.payload["team_id"])&.name || "team"
      "Bot handed off to #{team}"
    when "users:availability_changed"
      who = User.find_by(id: @event.payload["user_id"])&.name || "agent"
      "#{who} is now #{@event.payload["availability"]}"
    else
      @event.name
    end
  end
end
