module Dashboard
  module Flows
    class NodesController < ApplicationController
      include RequireAdmin

      before_action :load_flow
      before_action :load_node, only: [:update, :destroy]

      def create
        @node = @flow.flow_nodes.new(parsed_params)
        if @node.save
          redirect_to dashboard_flow_path(@flow)
        else
          render plain: @node.errors.full_messages.to_sentence, status: :unprocessable_content
        end
      rescue JSON::ParserError => e
        render plain: "content: #{e.message}", status: :unprocessable_content
      end

      def update
        if @node.update(parsed_params)
          redirect_to dashboard_flow_path(@flow)
        else
          render plain: @node.errors.full_messages.to_sentence, status: :unprocessable_content
        end
      rescue JSON::ParserError => e
        render plain: "content: #{e.message}", status: :unprocessable_content
      end

      def destroy
        if ConversationFlow.where(current_node_id: @node.id, status: "active").exists?
          render plain: "Node referenced by an active ConversationFlow.", status: :unprocessable_content
          return
        end
        @node.destroy
        redirect_to dashboard_flow_path(@flow)
      end

      private

      def load_flow
        @flow = Flow.find(params[:flow_id])
      end

      def load_node
        @node = @flow.flow_nodes.find(params[:id])
      end

      def parsed_params
        raw = params.require(:flow_node).permit(:node_type, :content, :next_node_id).to_h
        raw["content"] = JSON.parse(raw["content"]) if raw["content"].is_a?(String)
        raw
      end
    end
  end
end
