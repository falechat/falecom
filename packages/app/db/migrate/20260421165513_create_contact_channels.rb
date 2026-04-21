class CreateContactChannels < ActiveRecord::Migration[8.1]
  def change
    create_table :contact_channels do |t|
      t.references :contact, null: false, foreign_key: true
      t.references :channel, null: false, foreign_key: true
      t.string :source_id, null: false
      t.timestamps
    end

    add_index :contact_channels, [:channel_id, :source_id], unique: true, name: "index_contact_channels_on_channel_id_and_source_id"
  end
end
