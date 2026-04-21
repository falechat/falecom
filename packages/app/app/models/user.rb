class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :team_members, dependent: :destroy
  has_many :teams, through: :team_members
  has_many :assigned_conversations, class_name: "Conversation", foreign_key: :assignee_id

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  enum :role, {admin: "admin", supervisor: "supervisor", agent: "agent"}, validate: true
  enum :availability, {online: "online", busy: "busy", offline: "offline"}, validate: true

  validates :name, presence: true
  validates :role, presence: true
  validates :email_address, presence: true, uniqueness: true
end
