class FlowNode < ApplicationRecord
  belongs_to :flow
  belongs_to :next_node, class_name: "FlowNode", optional: true

  enum :node_type, {
    message: "message",
    menu: "menu",
    collect: "collect",
    handoff: "handoff",
    branch: "branch"
  }, validate: true, prefix: :type

  validates :content, presence: true
end
