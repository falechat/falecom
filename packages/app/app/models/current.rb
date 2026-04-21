class Current < ActiveSupport::CurrentAttributes
  attribute :session
  attribute :user

  def session=(new_session)
    super
    self.user = new_session&.user
  end
end
