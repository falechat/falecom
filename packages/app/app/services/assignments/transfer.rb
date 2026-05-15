module Assignments
  class Transfer
    def self.call(**kwargs) = new(**kwargs).call

    def initialize(conversation:, actor:, to_team: nil, to_user: nil, note: nil)
      @conversation = conversation
      @to_team = to_team
      @to_user = to_user
      @note = note
      @actor = actor
    end

    def call
      authorize!
      validate_target!

      from_team_id = @conversation.team_id
      from_user_id = @conversation.assignee_id

      target_team = @to_team || @conversation.team
      status = @to_user ? "assigned" : "queued"

      ActiveRecord::Base.transaction do
        @conversation.update!(team: target_team, assignee: @to_user, status: status)
        create_note_message if @note.present?
        Events::Emit.call(
          name: "conversations:transferred",
          subject: @conversation,
          actor: @actor,
          payload: {
            from_team_id: from_team_id, to_team_id: target_team&.id,
            from_user_id: from_user_id, to_user_id: @to_user&.id,
            note: @note
          }
        )
      end

      if @to_team && @to_user.nil?
        AutoAssignJob.perform_later(@conversation.id)
      end

      broadcast_transfer(from_user_id, from_team_id)
      @conversation
    end

    private

    def authorize!
      raise FaleCom::AuthorizationError unless ConversationPolicy.new(@actor, @conversation).can_transfer?
    end

    def validate_target!
      if @to_team && !@conversation.channel.teams.exists?(@to_team.id)
        raise FaleCom::ValidationError, "Team does not attend this channel"
      end
      if @to_user && @to_team && !@to_team.users.exists?(@to_user.id)
        raise FaleCom::ValidationError, "User is not a member of the target team"
      end
    end

    def create_note_message
      Messages::Create.call(
        conversation: @conversation,
        direction: "outbound",
        content: @note,
        content_type: "text",
        status: "received",
        sender: nil
      )
    end

    def broadcast_transfer(_from_user_id, _from_team_id)
      # Plan 06f wires the real Turbo Stream targets.
      nil
    end
  end
end
