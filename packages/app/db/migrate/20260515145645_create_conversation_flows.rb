class CreateConversationFlows < ActiveRecord::Migration[8.1]
  def change
    create_table :conversation_flows do |t|
      t.references :conversation, null: false, foreign_key: true
      t.references :flow, null: false, foreign_key: true
      t.references :current_node, foreign_key: {to_table: :flow_nodes}
      t.jsonb :state, null: false, default: {}
      t.string :status, null: false, default: "active"
      t.datetime :started_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :last_interaction_at
      t.timestamps
    end

    add_check_constraint :conversation_flows,
      "status IN ('active','completed','abandoned')",
      name: "conversation_flows_status_check"

    add_index :conversation_flows, :conversation_id,
      unique: true,
      where: "status = 'active'",
      name: "index_conversation_flows_one_active_per_conversation"
  end
end
