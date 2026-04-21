class CreateMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :messages do |t|
      t.references :conversation, null: false, foreign_key: true
      t.references :channel, null: false, foreign_key: true
      t.string :direction, null: false
      t.text :content, null: true
      t.string :content_type, null: false, default: "text"
      t.string :status, null: false, default: "received"
      t.string :external_id, null: true
      t.string :sender_type, null: true
      t.bigint :sender_id, null: true
      t.string :reply_to_external_id, null: true
      t.text :error, null: true
      t.jsonb :metadata, null: false, default: {}
      t.jsonb :raw, null: true
      t.datetime :sent_at, null: true
      t.timestamps
    end

    add_index :messages, [:conversation_id, :created_at]
    add_index :messages, [:channel_id, :external_id],
      unique: true,
      where: "external_id IS NOT NULL",
      name: "index_messages_on_channel_id_and_external_id"
    add_index :messages, [:sender_type, :sender_id]

    add_check_constraint :messages,
      "direction IN ('inbound','outbound')",
      name: "messages_direction_check"
    add_check_constraint :messages,
      "content_type IN ('text','image','audio','video','document','location','contact_card','input_select','button_reply','template')",
      name: "messages_content_type_check"
    add_check_constraint :messages,
      "status IN ('received','pending','sent','delivered','read','failed')",
      name: "messages_status_check"
  end
end
