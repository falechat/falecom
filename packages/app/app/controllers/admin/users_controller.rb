module Admin
  class UsersController < BaseController
    before_action :load_user, only: [:edit, :update, :destroy]

    def index
      @users = User.includes(:teams).order(:name)
    end

    def new
      @user = User.new
    end

    def create
      @user = User.new(user_params)
      if @user.save
        sync_teams(team_ids)
        redirect_to admin_users_path
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
    end

    def update
      attrs = user_params
      attrs.delete(:password) if attrs[:password].blank?
      if @user.update(attrs)
        sync_teams(team_ids)
        redirect_to admin_users_path
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @user.destroy
      redirect_to admin_users_path
    end

    private

    def load_user
      @user = User.find(params[:id])
    end

    def user_params
      params.require(:user).permit(:name, :email_address, :role, :availability, :password)
    end

    def team_ids
      params.require(:user).permit(team_ids: [])[:team_ids]
    end

    def sync_teams(ids)
      return if ids.nil?
      TeamMember.where(user: @user).delete_all
      Array(ids).reject(&:blank?).each { |tid| TeamMember.create!(user: @user, team_id: tid) }
    end
  end
end
