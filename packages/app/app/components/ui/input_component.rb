# frozen_string_literal: true

module Ui
  class InputComponent < ViewComponent::Base
    def initialize(name:, type: "text", value: nil, placeholder: nil, required: false, autofocus: false, autocomplete: nil, **attrs)
      @name = name
      @type = type
      @value = value
      @placeholder = placeholder
      @required = required
      @autofocus = autofocus
      @autocomplete = autocomplete
      @attrs = attrs
    end
  end
end
