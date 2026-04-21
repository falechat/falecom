class AutomationRule < ApplicationRecord
  validates :event_name, presence: true
end
