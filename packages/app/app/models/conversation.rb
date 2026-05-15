class Conversation < ApplicationRecord
  enum :status, {
    bot: "bot",
    queued: "queued",
    assigned: "assigned",
    resolved: "resolved"
  }, validate: true

  belongs_to :channel
  belongs_to :contact
  belongs_to :contact_channel
  belongs_to :assignee, class_name: "User", optional: true
  belongs_to :team, optional: true

  has_many :messages, dependent: :destroy
  has_many :conversation_flows, dependent: :destroy
  has_one :conversation_flow, -> { where(status: "active") }, inverse_of: :conversation

  validates :display_id, presence: true
end
