module Contacts
  # Merges a hash of {key => value-or-nil} into Contact#additional_attributes.
  # nil values delete the key.
  class UpdateAttributes
    def self.call(contact:, additional_attributes:)
      current = contact.additional_attributes || {}
      next_attrs = current.merge(additional_attributes.stringify_keys)
      next_attrs.reject! { |_k, v| v.nil? }
      contact.update!(additional_attributes: next_attrs)
      contact
    end
  end
end
