class CreateContacts < ActiveRecord::Migration[8.1]
  def change
    create_table :contacts do |t|
      t.string :name
      t.string :email
      t.string :phone_number
      t.string :identifier
      t.jsonb :additional_attributes, null: false, default: {}

      t.timestamps
    end
  end
end
