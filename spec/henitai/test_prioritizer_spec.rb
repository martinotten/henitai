# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::TestPrioritizer do
  it "keeps the original order when no history is available" do
    tests = %w[spec/a_spec.rb spec/b_spec.rb spec/c_spec.rb]

    expect(described_class.new.sort(tests, nil, nil)).to eq(tests)
  end

  it "prioritizes tests with higher kill counts first" do
    tests = %w[spec/a_spec.rb spec/b_spec.rb spec/c_spec.rb]
    history = {
      "spec/b_spec.rb" => 5,
      "spec/a_spec.rb" => 1
    }

    expect(described_class.new.sort(tests, nil, history)).to eq(
      %w[spec/b_spec.rb spec/a_spec.rb spec/c_spec.rb]
    )
  end
end
