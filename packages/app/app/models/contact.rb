class Contact < ApplicationRecord
  has_many :contact_channels, dependent: :destroy
  has_many :channels, through: :contact_channels
  has_many :conversations, dependent: :restrict_with_error
end
