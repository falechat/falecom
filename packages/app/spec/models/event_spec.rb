require "rails_helper"

RSpec.describe Event, type: :model do
  # A persisted User is used as subject/actor throughout this spec.
  # The Conversation-as-subject case is covered in conversation_spec.rb and event_emit_spec.rb
  # once the Conversation model exists (Phase C).

  let(:user) do
    User.create!(
      name: "Test User",
      email_address: "event_test@example.com",
      password: "password123",
      role: "agent"
    )
  end

  it "validates presence of name, subject_type, subject_id" do
    event = Event.new
    expect(event).not_to be_valid
    expect(event.errors[:name]).not_to be_empty
    expect(event.errors[:subject_type]).not_to be_empty
    expect(event.errors[:subject_id]).not_to be_empty
  end

  it "belongs to subject polymorphically" do
    reflection = Event.reflect_on_association(:subject)
    expect(reflection).not_to be_nil
    expect(reflection.options[:polymorphic]).to be true
  end

  it "belongs to actor polymorphically, optional" do
    reflection = Event.reflect_on_association(:actor)
    expect(reflection).not_to be_nil
    expect(reflection.options[:polymorphic]).to be true
    expect(reflection.options[:optional]).to be true
  end

  it "has no updated_at column (immutable)" do
    expect(Event.column_names.include?("updated_at")).to be false
  end

  it "can be created via Event.create! with a Conversation subject and a User actor" do
    # Using User as subject until Conversation model exists (Phase C)
    event = Event.create!(
      name: "conversations:created",
      subject: user,
      actor: user,
      payload: {foo: "bar"}
    )
    expect(event.persisted?).to be true
    expect(event.name).to eq("conversations:created")
    expect(event.subject).to eq(user)
    expect(event.actor).to eq(user)
  end

  it "can be created with an actor of nil (system events)" do
    event = Event.create!(
      name: "messages:inbound",
      subject: user,
      actor: nil,
      payload: {}
    )
    expect(event.persisted?).to be true
    expect(event.actor_type).to be_nil
    expect(event.actor_id).to be_nil
  end
end
