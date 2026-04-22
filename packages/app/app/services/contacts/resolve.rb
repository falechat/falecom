module Contacts
  # Resolves (or creates) a Contact + ContactChannel pair for an inbound
  # payload's `contact` section.
  #
  # Two paths:
  #   1. Exact match on (channel, source_id) → return existing; merge non-blank fields.
  #   2. No match → universal dedup on phone_number or email; reuse that Contact
  #      if present, else create a new one. Link a fresh ContactChannel either way.
  #
  # Cross-instance match (same source_id on other channels of same type) is
  # out of scope for Plan 04 — deferred per Spec 04 v2 § Out of scope.
  class Resolve
    MERGEABLE_FIELDS = %w[name phone_number email avatar_url].freeze

    def self.call(channel, contact_data)
      contact_channel = ContactChannel.find_or_initialize_by(
        channel: channel,
        source_id: contact_data.fetch("source_id")
      )

      if contact_channel.new_record?
        create_path(channel, contact_channel, contact_data)
      else
        reuse_path(contact_channel, contact_data)
      end
    end

    def self.create_path(_channel, contact_channel, contact_data)
      contact = find_existing_contact(contact_data) || Contact.create!(
        name: contact_data["name"],
        phone_number: contact_data["phone_number"],
        email: contact_data["email"]
      )

      contact_channel.contact = contact
      contact_channel.save!

      Events::Emit.call(name: "contacts:created", subject: contact, actor: :system) if contact.previously_new_record?
      Events::Emit.call(name: "contact_channels:created", subject: contact_channel, actor: :system)

      [contact, contact_channel]
    end

    def self.reuse_path(contact_channel, contact_data)
      contact = contact_channel.contact
      merge_contact_fields!(contact, contact_data)
      [contact, contact_channel]
    end

    def self.find_existing_contact(contact_data)
      if contact_data["phone_number"].present?
        hit = Contact.find_by(phone_number: contact_data["phone_number"])
        return hit if hit
      end
      if contact_data["email"].present?
        return Contact.find_by(email: contact_data["email"])
      end
      nil
    end

    # Provider-reported data never overwrites an existing non-blank field.
    # Two exceptions (applied via other code paths, not this helper):
    #   - Bot-collected values in Flows::Handoff (Spec 07).
    #   - Manual agent edits in the dashboard (Spec 06).
    def self.merge_contact_fields!(contact, contact_data)
      updates = {}
      MERGEABLE_FIELDS.each do |field|
        incoming = contact_data[field]
        next if incoming.blank?
        next if contact.public_send(field).present?
        updates[field] = incoming
      end
      contact.update!(updates) if updates.any?
    end

    private_class_method :create_path, :reuse_path, :find_existing_contact, :merge_contact_fields!
  end
end
