class ContactSidebarComponent < ViewComponent::Base
  def initialize(contact: nil, current_conversation: nil)
    @contact = contact
    @current = current_conversation
  end

  def attributes_pairs
    (@contact&.additional_attributes || {}).to_a
  end

  def history
    return [] if @contact.nil?
    ::Conversation.where(contact_id: @contact.id).where.not(id: @current&.id).order(created_at: :desc).limit(20)
  end
end
