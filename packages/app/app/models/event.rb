class Event < ApplicationRecord
  belongs_to :subject, polymorphic: true
  belongs_to :actor, polymorphic: true, optional: true

  validates :name, presence: true
  validates :subject_type, presence: true
  validates :subject_id, presence: true
end
