module RequireAdmin
  extend ActiveSupport::Concern

  included do
    before_action :require_admin!
  end

  private

  def require_admin!
    head :forbidden unless Current.user&.admin?
  end
end
