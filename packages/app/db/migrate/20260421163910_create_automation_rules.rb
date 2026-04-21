class CreateAutomationRules < ActiveRecord::Migration[8.1]
  def change
    create_table :automation_rules do |t|
      t.string :event_name, null: false
      t.jsonb :conditions, null: false, default: []
      t.jsonb :actions, null: false, default: []
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :automation_rules, [:event_name, :active]
  end
end
