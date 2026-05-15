module Contacts
  # Manual contact creation. Idempotent on (channel, source_id) when both
  # are provided: returns the existing contact instead of duplicating.
  class Create
    def self.call(name: nil, phone_number: nil, email: nil, channel: nil, source_id: nil)
      contact = if channel && source_id
        ContactChannel.find_by(channel: channel, source_id: source_id)&.contact ||
          Contact.create!(name: name, phone_number: phone_number, email: email)
      else
        Contact.create!(name: name, phone_number: phone_number, email: email)
      end

      if channel && source_id
        ContactChannel.find_or_create_by!(contact: contact, channel: channel, source_id: source_id)
      end

      contact
    end
  end
end
