module Flows
  class Advance
    MAX_STEPS_PER_ADVANCE = 50

    def self.call(conversation, inbound_message, step_count: 0)
      new(conversation, inbound_message, step_count).call
    end

    def initialize(conversation, inbound_message, step_count)
      @conversation = conversation
      @inbound = inbound_message
      @step = step_count
    end

    def call
      return abandon! if @step > MAX_STEPS_PER_ADVANCE

      cf = @conversation.conversation_flow || @conversation.reload.conversation_flow
      return Flows::Start.call(@conversation) if cf.nil? || cf.status != "active"

      node = cf.current_node
      return Flows::Handoff.call(@conversation, cf) unless node

      send("handle_#{node.node_type}", cf, node)
    end

    private

    def handle_message(cf, node)
      send_text(node.content["text"])
      advance_to(cf, node.next_node_id, node)
      auto_chain(cf)
    end

    def handle_menu(cf, node)
      if @inbound.nil?
        send_text(Flows::MenuFormatter.call(node.content))
        return
      end
      selected = (node.content["options"] || []).find { |o| o["key"] == @inbound.content.to_s.strip }
      if selected
        advance_to(cf, selected["next_node_id"], node)
        auto_chain(cf)
      else
        send_text("Não entendi. Por favor, escolha uma opção:\n\n#{Flows::MenuFormatter.call(node.content)}")
      end
    end

    def handle_collect(cf, node)
      if @inbound.nil?
        send_text(node.content["text"])
        return
      end
      value = @inbound.content.to_s.strip
      if Flows::Validators.call(value, node.content["validation"])
        cf.update!(state: cf.state.merge(node.content["variable"] => value))
        advance_to(cf, node.next_node_id, node)
        auto_chain(cf)
      else
        send_text("Resposta inválida. #{node.content["text"]}")
      end
    end

    def handle_branch(cf, node)
      var = node.content["variable"]
      val = cf.state[var]
      condition = (node.content["conditions"] || []).find { |c| c["value"] == val }
      next_id = condition ? condition["next_node_id"] : node.content["default_next_node_id"]
      advance_to(cf, next_id, node)
      auto_chain(cf)
    end

    def handle_handoff(cf, node)
      Flows::Handoff.call(@conversation, cf, node)
    end

    def advance_to(cf, next_node_id, current_node)
      cf.update!(current_node_id: next_node_id, last_interaction_at: Time.current)
      Events::Emit.call(name: "flows:advanced", subject: @conversation, actor: :bot,
        payload: {node_id: current_node.id, node_type: current_node.node_type})
    end

    def auto_chain(cf)
      cf.reload
      next_node = cf.current_node
      return unless next_node
      return unless %w[message branch handoff].include?(next_node.node_type)
      Flows::Advance.call(@conversation, nil, step_count: @step + 1)
    end

    def send_text(content)
      ::Dispatch::Outbound.call(conversation: @conversation, content: content, content_type: "text", actor: :bot)
    end

    def abandon!
      cf = @conversation.conversation_flow
      cf&.update!(status: "abandoned")
      @conversation.update!(status: "queued")
      Events::Emit.call(name: "flows:abandoned", subject: @conversation, actor: :bot, payload: {
        reason: "max_steps_exceeded", step_count: @step
      })
    end
  end
end
