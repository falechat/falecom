require "rails_helper"

RSpec.describe Flows::Validators do
  it "any -> always true" do
    expect(described_class.call("anything", "any")).to be true
    expect(described_class.call("", "any")).to be true
  end

  it "email -> only RFC-ish" do
    expect(described_class.call("a@b.co", "email")).to be true
    expect(described_class.call("nope", "email")).to be false
  end

  it "phone -> digits only with optional + and length >= 8" do
    expect(described_class.call("+5511999999999", "phone")).to be true
    expect(described_class.call("11999999", "phone")).to be true
    expect(described_class.call("abc", "phone")).to be false
  end

  it "number -> integer-coercible" do
    expect(described_class.call("42", "number")).to be true
    expect(described_class.call("abc", "number")).to be false
  end

  it "unknown validator defaults to any" do
    expect(described_class.call("x", "wat")).to be true
  end
end
