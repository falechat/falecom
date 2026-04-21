class CreateConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :conversations do |t|
      t.references :channel, null: false, foreign_key: true
      t.references :contact, null: false, foreign_key: true
      t.references :contact_channel, null: false, foreign_key: true
      t.string :status, null: false, default: "bot"
      t.bigint :assignee_id, null: true
      t.references :team, null: true, foreign_key: true
      t.integer :display_id, null: false
      t.datetime :last_activity_at, null: true
      t.jsonb :additional_attributes, null: false, default: {}
      t.timestamps
    end

    add_foreign_key :conversations, :users, column: :assignee_id
    add_index :conversations, :assignee_id

    add_index :conversations, [:status, :last_activity_at], order: {last_activity_at: :desc}
    add_index :conversations, [:channel_id, :status]
    add_index :conversations, [:assignee_id, :status]
    add_index :conversations, [:team_id, :status]
    add_index :conversations, :display_id, unique: true
    add_index :conversations, :contact_channel_id,
      unique: true,
      where: "status != 'resolved'",
      name: "index_conversations_open_per_contact_channel"

    add_check_constraint :conversations,
      "status IN ('bot','queued','assigned','resolved')",
      name: "conversations_status_check"
  end
end
