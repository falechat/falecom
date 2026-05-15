class AddActiveFlowIdFkToChannels < ActiveRecord::Migration[8.1]
  def change
    add_foreign_key :channels, :flows, column: :active_flow_id
    add_index :channels, :active_flow_id unless index_exists?(:channels, :active_flow_id)
  end
end
