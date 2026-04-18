# frozen_string_literal: true

module Ui
  class SidebarComponent < ViewComponent::Base
    def initialize(items: [])
      @items = items
    end
  end
end
