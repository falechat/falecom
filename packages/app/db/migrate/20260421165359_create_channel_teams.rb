class CreateChannelTeams < ActiveRecord::Migration[8.1]
  def change
    create_table :channel_teams do |t|
      t.references :channel, null: false, foreign_key: true
      t.references :team, null: false, foreign_key: true
      t.timestamps
    end

    add_index :channel_teams, [:channel_id, :team_id], unique: true, name: "index_channel_teams_on_channel_id_and_team_id"
  end
end
