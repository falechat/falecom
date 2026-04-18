# frozen_string_literal: true

module Ui
  class NavbarComponent < ViewComponent::Base
    def initialize(brand:, user: nil)
      @brand = brand
      @user = user
    end
  end
end
