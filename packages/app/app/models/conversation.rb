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

  validates :display_id, presence: true
end
