class ExtendUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :name, :string, null: false
    add_column :users, :role, :string, null: false
    add_column :users, :availability, :string, null: false, default: "offline"

    add_check_constraint :users, "role IN ('admin','supervisor','agent')", name: "users_role_check"
    add_check_constraint :users, "availability IN ('online','busy','offline')", name: "users_availability_check"
  end
end
