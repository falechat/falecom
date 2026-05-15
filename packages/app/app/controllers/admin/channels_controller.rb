module Admin
  class ChannelsController < BaseController
    before_action :load_channel, only: [:edit, :update, :destroy]

    def index
      @channels = Channel.order(:name)
    end

    def new
      @channel = Channel.new
    end

    def create
      @channel = Channel.new(parsed_params)
      if @channel.save
        redirect_to admin_channels_path, notice: "Channel created"
      else
        render :new, status: :unprocessable_content
      end
    rescue JSON::ParserError => e
      @channel ||= Channel.new
      @channel.errors.add(:credentials, e.message)
      render :new, status: :unprocessable_content
    end

    def edit
    end

    def update
      if @channel.update(parsed_params)
        redirect_to admin_channels_path, notice: "Updated"
      else
        render :edit, status: :unprocessable_content
      end
    rescue JSON::ParserError => e
      @channel.errors.add(:credentials, e.message)
      render :edit, status: :unprocessable_content
    end

    def destroy
      @channel.update!(active: false)
      redirect_to admin_channels_path, notice: "Deactivated"
    end

    private

    def load_channel
      @channel = Channel.find(params[:id])
    end

    def parsed_params
      raw = params.require(:channel).permit(:name, :channel_type, :identifier, :active, :auto_assign, :credentials, :auto_assign_config).to_h
      if raw["credentials"].is_a?(String) && raw["credentials"].present?
        raw["credentials"] = JSON.parse(raw["credentials"])
      end
      if raw["auto_assign_config"].is_a?(String) && raw["auto_assign_config"].present?
        raw["auto_assign_config"] = JSON.parse(raw["auto_assign_config"])
      end
      raw
    end
  end
end
