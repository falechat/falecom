require "dry-types"

module FaleComChannel
  module Payload
    module Types
      include Dry.Types()

      CONTENT_TYPES = %w[text image audio video document location contact_card input_select button_reply template].freeze
    end
  end
end
