# frozen_string_literal: true

module Ui
  class FormFieldComponent < ViewComponent::Base
    renders_one :label, Ui::LabelComponent
    renders_one :input, Ui::InputComponent

    def initialize(error: nil)
      @error = error
    end
  end
end
