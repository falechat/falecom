class CreateEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :events do |t|
      t.string :name, null: false
      t.string :actor_type
      t.bigint :actor_id
      t.string :subject_type, null: false
      t.bigint :subject_id, null: false
      t.jsonb :payload, null: false, default: {}
      t.datetime :created_at, null: false
    end

    add_index :events, [:name, :created_at], order: {created_at: :desc}
    add_index :events, [:subject_type, :subject_id, :created_at], order: {created_at: :desc}
    add_index :events, [:actor_type, :actor_id, :created_at], order: {created_at: :desc}
    add_index :events, :created_at, order: {created_at: :desc}
  end
end
