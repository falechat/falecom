module Events
  class Emit
    def self.call(name:, subject:, actor: :default, payload: {})
      raise ArgumentError, "name must be present" if name.blank?
      raise ArgumentError, "subject must be present" if subject.nil?

      actor = Current.user if actor == :default
      actor_type, actor_id = actor_columns_for(actor)

      Event.create!(
        name: name,
        subject: subject,
        actor_type: actor_type,
        actor_id: actor_id,
        payload: payload
      )
    end

    def self.actor_columns_for(actor)
      case actor
      when nil, :system, :bot then [nil, nil]
      when ActiveRecord::Base then [actor.class.polymorphic_name, actor.id]
      else raise ArgumentError, "unknown actor: #{actor.inspect}"
      end
    end
    private_class_method :actor_columns_for
  end
end
