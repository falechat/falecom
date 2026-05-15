module Flows
  class Handoff
    def self.call(conversation, conversation_flow, node = nil)
      new(conversation, conversation_flow, node).call
    end

    def initialize(conversation, conversation_flow, node)
      @conversation = conversation
      @cf = conversation_flow
      @content = node&.content || {}
    end

    def call
      send_handoff_message
      apply_collected_name
      complete_flow
      queue_conversation
      emit_events
      enqueue_auto_assign
    end

    private

    def send_handoff_message
      return if @content["message"].blank?
      ::Dispatch::Outbound.call(
        conversation: @conversation,
        content: @content["message"],
        content_type: "text",
        actor: :bot
      )
    end

    def apply_collected_name
      return unless @content["assign_collected_name"]
      name = @cf.state["contact_name"]
      return if name.blank?
      @conversation.contact.update!(name: name)
    end

    def complete_flow
      @cf.update!(status: "completed", current_node: nil)
    end

    def queue_conversation
      team = @content["team_id"] ? Team.find_by(id: @content["team_id"]) : nil
      @conversation.update!(status: "queued", team: team)
    end

    def emit_events
      ::Events::Emit.call(name: "flows:handoff", subject: @conversation, actor: :bot, payload: {
        flow_id: @cf.flow_id, team_id: @conversation.team_id, collected_state: @cf.state
      })
      ::Events::Emit.call(name: "conversations:status_changed", subject: @conversation, actor: :bot, payload: {
        from: "bot", to: "queued"
      })
    end

    def enqueue_auto_assign
      return unless @conversation.channel.auto_assign?
      AutoAssignJob.perform_later(@conversation.id, depth: 0)
    end
  end
end
