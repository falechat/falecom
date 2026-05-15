module Admin
  class TeamsController < BaseController
    before_action :load_team, only: [:edit, :update, :destroy]

    def index
      @teams = Team.includes(:users, :channels).order(:name)
    end

    def new
      @team = Team.new
    end

    def create
      @team = Team.new(name: team_params[:name])
      if @team.save
        sync(team_params[:user_ids], team_params[:channel_ids])
        redirect_to admin_teams_path, notice: "Created"
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
    end

    def update
      if @team.update(name: team_params[:name])
        sync(team_params[:user_ids], team_params[:channel_ids])
        redirect_to admin_teams_path
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @team.destroy
      redirect_to admin_teams_path
    end

    private

    def load_team
      @team = Team.find(params[:id])
    end

    def team_params
      params.require(:team).permit(:name, user_ids: [], channel_ids: [])
    end

    def sync(user_ids, channel_ids)
      unless user_ids.nil?
        TeamMember.where(team: @team).delete_all
        Array(user_ids).reject(&:blank?).each { |uid| TeamMember.create!(team: @team, user_id: uid) }
      end
      unless channel_ids.nil?
        ChannelTeam.where(team: @team).delete_all
        Array(channel_ids).reject(&:blank?).each { |cid| ChannelTeam.create!(team: @team, channel_id: cid) }
      end
    end
  end
end
