# frozen_string_literal: true

module Ui
  class LabelComponent < ViewComponent::Base
    def initialize(text:, for_id: nil, required: false)
      @text = text
      @for_id = for_id
      @required = required
    end
  end
end
