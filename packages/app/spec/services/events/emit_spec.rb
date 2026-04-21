require "rails_helper"

RSpec.describe Events::Emit do
  let(:user) { User.create!(name: "A", email_address: "a@example.com", password: "password123", role: "agent") }
  let(:contact) { Contact.create!(name: "C") }
  # Subject: any persisted record. Use another user as a stand-in until Conversation exists.
  let(:subject_record) { User.create!(name: "Subj", email_address: "s@example.com", password: "password123", role: "admin") }

  it "creates an Event with a User actor" do
    event = described_class.call(name: "conversations:created", subject: subject_record, actor: user)
    expect(event.name).to eq "conversations:created"
    expect(event.subject).to eq subject_record
    expect(event.actor).to eq user
  end

  it "creates an Event with a Contact actor" do
    event = described_class.call(name: "messages:inbound", subject: subject_record, actor: contact)
    expect(event.actor).to eq contact
  end

  it "creates an Event with actor :system (sets actor_type/actor_id to nil)" do
    event = described_class.call(name: "flows:handoff", subject: subject_record, actor: :system)
    expect(event.actor_type).to be_nil
    expect(event.actor_id).to be_nil
  end

  it "creates an Event with actor :bot (sets actor_type/actor_id to nil)" do
    event = described_class.call(name: "flows:started", subject: subject_record, actor: :bot)
    expect(event.actor_type).to be_nil
    expect(event.actor_id).to be_nil
  end

  it "falls back to Current.user when actor is not supplied" do
    Current.user = user
    event = described_class.call(name: "conversations:created", subject: subject_record)
    expect(event.actor).to eq user
  ensure
    Current.reset
  end

  it "falls back to nil actor when Current.user is not set and no actor supplied" do
    Current.reset
    event = described_class.call(name: "conversations:created", subject: subject_record)
    expect(event.actor_type).to be_nil
    expect(event.actor_id).to be_nil
  end

  it "raises ArgumentError when name is blank" do
    expect { described_class.call(name: "", subject: subject_record) }.to raise_error(ArgumentError)
  end

  it "raises when subject is nil" do
    expect { described_class.call(name: "x", subject: nil) }.to raise_error(ArgumentError)
  end

  it "stores payload verbatim" do
    event = described_class.call(name: "conversations:updated", subject: subject_record, payload: {foo: "bar"})
    expect(event.reload.payload).to eq({"foo" => "bar"})
  end

  it "returns the created Event" do
    event = described_class.call(name: "x", subject: subject_record)
    expect(event).to be_a(Event).and be_persisted
  end
end
