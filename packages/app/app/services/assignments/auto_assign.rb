module Assignments
  class AutoAssign
    def self.call(conversation)
      new(conversation).call
    end

    def initialize(conversation)
      @conversation = conversation
    end

    def call
      return unless @conversation.channel.auto_assign?
      return if @conversation.assignee_id.present?

      team = pick_team
      return unless team

      ActiveRecord::Base.transaction do
        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.send(:sanitize_sql_array,
            ["SELECT pg_advisory_xact_lock(hashtext(?))", "auto_assign_team_#{team.id}"])
        )

        agent = pick_agent(team)
        next unless agent

        @conversation.update!(assignee: agent, team: team, status: "assigned")
        Events::Emit.call(
          name: "conversations:assigned",
          subject: @conversation,
          actor: :system,
          payload: {assignee_id: agent.id, team_id: team.id, strategy: strategy}
        )
      end

      broadcast_assignment
    end

    private

    def config
      @conversation.channel.auto_assign_config.to_h
    end

    def strategy
      config["strategy"] || "round_robin"
    end

    def pick_team
      if (id = config["team_id"])
        Team.find_by(id: id)
      else
        @conversation.channel.teams.order(:id).first
      end
    end

    def pick_agent(team)
      pool = Assignments::EligibleAgents.call(team)
      case strategy
      when "capacity" then pick_by_capacity(pool)
      else pick_round_robin(pool)
      end
    end

    def pick_round_robin(pool)
      pool.left_outer_joins(:assigned_conversations)
        .where(conversations: {status: ["assigned", nil]})
        .group("users.id")
        .order(Arel.sql("COUNT(conversations.id) ASC"))
        .first
    end

    def pick_by_capacity(pool)
      cap = (config["capacity"] || 10).to_i
      pool.left_outer_joins(:assigned_conversations)
        .where(conversations: {status: ["assigned", nil]})
        .group("users.id")
        .having("COUNT(conversations.id) < ?", cap)
        .order(Arel.sql("COUNT(conversations.id) ASC"))
        .first
    end

    def broadcast_assignment
      # 06f wires the real Turbo Stream targets. Kept as a placeholder so the
      # call site is stable.
      nil
    end
  end
end
