# frozen_string_literal: true

require_relative "../../spec_helper"

# Pins every method's behaviour, so every mutant that changes behaviour must
# be detected. Survivors must be listed, with a reason, in expected.yml.
RSpec.describe Oracle::Pricing do
  subject(:pricing) { described_class.new }

  it "computes the rate from its own constant" do
    expect(described_class.rate).to eq(4)
  end

  it "adds the module tax" do
    expect([pricing.net(1), pricing.net(5)]).to eq([3, 7])
  end

  it "adds one to the parent total" do
    expect([pricing.total(2), pricing.total(5)]).to eq([5, 11])
  end

  it "yields the tier" do
    expect { |probe| pricing.each_tier(&probe) }.to yield_with_args(4)
  end

  it "returns the tier block's value" do
    expect(pricing.each_tier { |tier| tier * 10 }).to eq(40)
  end

  it "doubles without a block and yields with one" do
    expect([pricing.maybe_double(3), pricing.maybe_double(3) { |amount| amount + 100 }]).to eq([6, 103])
  end

  it "tags by size" do
    expect([2, 3, 4, 9].map { |amount| pricing.tagged(amount) }).to eq(%w[small:2 small:3 big:4 big:9])
  end

  it "sums the first elements plus one" do
    expect([pricing.firsts([[1, 2], [3, 4]]), pricing.firsts([[5, 0]])]).to eq([5, 6])
  end

  it "labels by width" do
    expect([0, 1, 2, 5].map { |width| pricing.label(width) }).to eq(%w[klein klein größe größe])
  end

  it "flags bulk counts" do
    expect([2, 3, 4, 9].map { |count| pricing.bulk?(count) }).to eq([false, false, true, true])
  end

  it "grades scores" do
    expect([10, 50, 51, 90, 91].map { |score| pricing.grade(score) }).to eq(%i[c c b b a])
  end

  it "applies the default discount" do
    expect([pricing.discounted(10), pricing.discounted(10, 3)]).to eq([8, 7])
  end

  it "finishes when done" do
    expect(pricing.finish(true)).to eq(:ok)
  end

  it "adds the private secret" do
    expect([pricing.masked(1), pricing.masked(4)]).to eq([12, 15])
  end

  it "keeps the secret private" do
    expect(described_class.private_method_defined?(:secret)).to be(true)
  end
end
