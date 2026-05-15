class CreateFlows < ActiveRecord::Migration[8.1]
  def change
    create_table :flows do |t|
      t.string :name, null: false
      t.text :description
      t.boolean :is_active, null: false, default: true
      t.integer :inactivity_threshold_hours, null: false, default: 24
      t.bigint :root_node_id
      t.bigint :short_greeting_node_id
      t.timestamps
    end

    add_index :flows, :is_active
  end
end
