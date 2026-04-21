class CreateChannels < ActiveRecord::Migration[8.1]
  def change
    create_table :channels do |t|
      t.string :channel_type, null: false
      t.string :identifier, null: false
      t.string :name, null: false
      t.boolean :active, null: false, default: true
      t.jsonb :config, null: false, default: {}
      t.text :credentials, null: false, default: "{}"
      t.boolean :auto_assign, null: false, default: false
      t.jsonb :auto_assign_config, null: false, default: {}
      t.boolean :greeting_enabled, null: false, default: false
      t.text :greeting_message
      t.bigint :active_flow_id

      t.timestamps
    end

    add_index :channels, [:channel_type, :identifier],
      unique: true,
      name: "index_channels_on_channel_type_and_identifier"

    add_index :channels, :active

    add_check_constraint :channels,
      "channel_type IN ('whatsapp_cloud','zapi','evolution','instagram','telegram')",
      name: "channels_channel_type_check"
  end
end
