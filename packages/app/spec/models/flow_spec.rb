require "rails_helper"

RSpec.describe Flow, type: :model do
  it "validates presence of name" do
    expect(Flow.new(name: nil)).not_to be_valid
  end

  it "defaults is_active to true and inactivity_threshold_hours to 24" do
    f = Flow.create!(name: "Atendimento")
    expect(f.is_active).to be true
    expect(f.inactivity_threshold_hours).to eq(24)
  end

  it "has_many flow_nodes (dependent: destroy)" do
    f = Flow.create!(name: "f")
    n = FlowNode.create!(flow: f, node_type: "message", content: {"text" => "hi"})
    expect { f.destroy }.to change(FlowNode, :count).by(-1)
    expect { n.reload }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "belongs_to root_node and short_greeting_node optionally" do
    f = Flow.create!(name: "f")
    expect(f.root_node).to be_nil
    expect(f.short_greeting_node).to be_nil
  end
end
