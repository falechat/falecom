class ConversationFlow < ApplicationRecord
  belongs_to :conversation
  belongs_to :flow
  belongs_to :current_node, class_name: "FlowNode", optional: true

  enum :status, {
    active: "active",
    completed: "completed",
    abandoned: "abandoned"
  }, validate: true
end
