class ConversationListComponent < ViewComponent::Base
  PAGE_SIZE = 25

  def initialize(conversations:, active_id: nil, view: "mine", page: 1)
    @conversations = conversations
    @active_id = active_id
    @view = view
    @page = [page.to_i, 1].max
  end

  def paged
    @conversations.offset((@page - 1) * PAGE_SIZE).limit(PAGE_SIZE)
  end

  def total
    @conversations.count
  end

  def total_pages
    (total / PAGE_SIZE.to_f).ceil
  end

  attr_reader :view, :page, :active_id
end
