module Dashboard
  class FlowsController < ApplicationController
    include RequireAdmin
    before_action :load_flow, only: [:show, :edit, :update, :destroy, :set_root]

    def index
      @flows = Flow.order(:name)
    end

    def new
      @flow = Flow.new
    end

    def create
      @flow = Flow.new(flow_params)
      if @flow.save
        redirect_to dashboard_flow_path(@flow)
      else
        render :new, status: :unprocessable_content
      end
    end

    def show
      @nodes = @flow.flow_nodes.order(:id)
    end

    def edit
      @nodes = @flow.flow_nodes.order(:id)
      render :show
    end

    def update
      if @flow.update(flow_params)
        redirect_to dashboard_flow_path(@flow)
      else
        @nodes = @flow.flow_nodes.order(:id)
        render :show, status: :unprocessable_content
      end
    end

    def destroy
      if Channel.where(active_flow_id: @flow.id).exists?
        render plain: "Flow is bound to a channel — deactivate it first.", status: :unprocessable_content
      else
        @flow.destroy
        redirect_to dashboard_flows_path
      end
    end

    def set_root
      node = @flow.flow_nodes.find(params[:node_id])
      @flow.update!(root_node: node)
      redirect_to dashboard_flow_path(@flow)
    end

    private

    def load_flow
      @flow = Flow.find(params[:id])
    end

    def flow_params
      params.require(:flow).permit(:name, :description, :is_active, :inactivity_threshold_hours)
    end
  end
end
