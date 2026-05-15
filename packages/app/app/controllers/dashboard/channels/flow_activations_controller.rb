module Dashboard
  module Channels
    class FlowActivationsController < ApplicationController
      include RequireAdmin

      def create
        channel = Channel.find(params[:channel_id])
        channel.update!(active_flow_id: params[:flow_id])
        redirect_back fallback_location: admin_channel_path(channel)
      end

      def destroy
        channel = Channel.find(params[:channel_id])
        channel.update!(active_flow_id: nil)
        redirect_back fallback_location: admin_channel_path(channel)
      end
    end
  end
end
