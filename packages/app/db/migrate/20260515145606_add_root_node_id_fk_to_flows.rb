class AddRootNodeIdFkToFlows < ActiveRecord::Migration[8.1]
  def change
    add_foreign_key :flows, :flow_nodes, column: :root_node_id
    add_foreign_key :flows, :flow_nodes, column: :short_greeting_node_id
    add_index :flows, :root_node_id
    add_index :flows, :short_greeting_node_id
  end
end
