# frozen_string_literal: true

module Ui
  class ButtonComponent < ViewComponent::Base
    def initialize(label:, type: "button", variant: "primary", href: nil, method: nil, **attrs)
      @label = label
      @type = type
      @variant = variant
      @href = href
      @method = method
      @attrs = attrs
    end

    private

    def button_classes
      base = "inline-flex items-center justify-center rounded-md px-4 py-2 text-sm font-medium transition-colors focus:outline-none focus:ring-2 focus:ring-offset-2"
      variant_classes = case @variant
      when "primary" then "bg-blue-600 text-white hover:bg-blue-700 focus:ring-blue-500"
      when "secondary" then "border border-slate-300 bg-white text-slate-700 hover:bg-slate-50 focus:ring-blue-500 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-200"
      else "bg-blue-600 text-white hover:bg-blue-700"
      end
      extra = @attrs[:class] || ""
      "#{base} #{variant_classes} #{extra}".strip
    end
  end
end
