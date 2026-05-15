class CreateFlowNodes < ActiveRecord::Migration[8.1]
  def change
    create_table :flow_nodes do |t|
      t.references :flow, null: false, foreign_key: true
      t.string :node_type, null: false
      t.jsonb :content, null: false, default: {}
      t.references :next_node, foreign_key: {to_table: :flow_nodes}
      t.timestamps
    end

    add_check_constraint :flow_nodes,
      "node_type IN ('message','menu','collect','handoff','branch')",
      name: "flow_nodes_node_type_check"
  end
end
