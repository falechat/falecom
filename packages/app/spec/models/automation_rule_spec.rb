require "rails_helper"

RSpec.describe AutomationRule, type: :model do
  it "validates presence of event_name" do
    rule = AutomationRule.new(event_name: "")
    expect(rule).not_to be_valid
    expect(rule.errors[:event_name]).not_to be_empty
  end

  it "defaults conditions to [], actions to [], active to true" do
    rule = AutomationRule.create!(event_name: "conversations:created")
    rule.reload
    expect(rule.conditions).to eq([])
    expect(rule.actions).to eq([])
    expect(rule.active).to be true
  end
end
