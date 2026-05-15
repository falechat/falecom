# Gate Turbo::StreamsChannel subscriptions through ConversationStreamGate so
# an agent can only subscribe to streams they're authorized to see.
Rails.application.config.to_prepare do
  Turbo::StreamsChannel.class_eval do
    unless method_defined?(:subscribed_without_gating)
      alias_method :subscribed_without_gating, :subscribed

      def subscribed
        name = verified_stream_name_from_params
        return reject unless name && ConversationStreamGate.allowed?(connection.current_user, name)
        stream_from name
      end
    end
  end
end
