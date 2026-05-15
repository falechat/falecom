class Channel < ApplicationRecord
  serialize :credentials, coder: JSON
  encrypts :credentials

  enum :channel_type, {
    whatsapp_cloud: "whatsapp_cloud",
    zapi: "zapi",
    evolution: "evolution",
    instagram: "instagram",
    telegram: "telegram"
  }, validate: true

  validates :channel_type, :identifier, :name, presence: true

  has_many :channel_teams, dependent: :destroy
  has_many :teams, through: :channel_teams
  has_many :contact_channels, dependent: :destroy
  has_many :conversations, dependent: :restrict_with_error
  has_many :messages, dependent: :restrict_with_error

  belongs_to :active_flow, class_name: "Flow", optional: true
end
