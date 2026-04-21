class ContactChannel < ApplicationRecord
  belongs_to :contact
  belongs_to :channel

  validates :source_id, presence: true
end
