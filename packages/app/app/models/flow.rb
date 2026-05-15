class Flow < ApplicationRecord
  has_many :flow_nodes, dependent: :destroy
  belongs_to :root_node, class_name: "FlowNode", optional: true
  belongs_to :short_greeting_node, class_name: "FlowNode", optional: true

  validates :name, presence: true
end
