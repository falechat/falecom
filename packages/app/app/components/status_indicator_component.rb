class StatusIndicatorComponent < ViewComponent::Base
  ICONS = {
    "pending" => {icon: "clock", color: "text-gray-400"},
    "sent" => {icon: "check", color: "text-gray-400"},
    "delivered" => {icon: "check-double", color: "text-gray-400"},
    "read" => {icon: "check-double", color: "text-blue-500"},
    "failed" => {icon: "exclamation", color: "text-red-500"}
  }.freeze

  SVGS = {
    "clock" => '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="w-4 h-4"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>',
    "check" => '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="w-4 h-4"><path d="M5 12l4 4L19 8"/></svg>',
    "check-double" => '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="w-4 h-4"><path d="M2 12l4 4 8-8"/><path d="M10 16l4 4 8-12"/></svg>',
    "exclamation" => '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="w-4 h-4"><circle cx="12" cy="12" r="9"/><path d="M12 7v5"/><circle cx="12" cy="16" r="0.5" fill="currentColor"/></svg>'
  }.freeze

  def initialize(message:)
    @message = message
    @config = ICONS.fetch(message.status)
  end

  def icon_html
    SVGS.fetch(@config[:icon]).html_safe
  end

  attr_reader :message, :config
end
