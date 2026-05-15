require "rails_helper"

RSpec.describe FlowNode, type: :model do
  let(:flow) { Flow.create!(name: "f") }

  it "validates node_type enum" do
    expect { FlowNode.create!(flow: flow, node_type: "lol", content: {"x" => 1}) }
      .to raise_error(ActiveRecord::RecordInvalid)
  end

  it "validates content presence" do
    expect(FlowNode.new(flow: flow, node_type: "message", content: nil)).not_to be_valid
  end

  %w[message menu collect handoff branch].each do |t|
    it "accepts node_type=#{t}" do
      expect(FlowNode.create!(flow: flow, node_type: t, content: {"x" => 1})).to be_persisted
    end
  end

  it "belongs_to next_node optionally" do
    n1 = FlowNode.create!(flow: flow, node_type: "message", content: {"text" => "a"})
    n2 = FlowNode.create!(flow: flow, node_type: "message", content: {"text" => "b"}, next_node: n1)
    expect(n2.next_node).to eq(n1)
  end
end
