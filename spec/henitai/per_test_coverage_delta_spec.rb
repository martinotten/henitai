# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::PerTestCoverageDelta do
  def delta(current, previous = [])
    described_class.new.executed_lines(current, previous)
  end

  it "returns lines whose cumulative count increased" do
    expect(delta([nil, 1, 0, 3], [nil, 1, 0, 2])).to eq([4])
  end

  it "treats a missing previous count as zero" do
    expect(delta([nil, 1, 0, 3])).to eq([2, 4])
  end

  it "reads lines from symbol- and string-keyed coverage hashes" do
    expect([delta({ lines: [nil, 1] }), delta({ "lines" => [nil, 1] })])
      .to eq([[2], [2]])
  end

  it "attributes a called endless method's line, which line coverage never counts" do
    current = { lines: [1, 1, nil], methods: { [Object, :x, 2, 2, 2, 17] => 1 } }
    previous = { lines: [1, 1, nil], methods: { [Object, :x, 2, 2, 2, 17] => 0 } }

    expect(delta(current, previous)).to eq([2])
  end

  it "attributes every untracked line of a called multi-line endless method" do
    current = { lines: [1, 1, nil, nil], methods: { [Object, :x, 2, 2, 4, 9] => 2 } }
    previous = { lines: [1, 1, nil, nil], methods: { [Object, :x, 2, 2, 4, 9] => 1 } }

    expect(delta(current, previous)).to eq([2, 3, 4])
  end

  it "leaves tracked body lines of a called method to line-count deltas" do
    current = { lines: [1, 1, 0, 1, nil], methods: { [Object, :x, 2, 2, 5, 5] => 1 } }
    previous = { lines: [1, 1, 0, 0, nil], methods: { [Object, :x, 2, 2, 5, 5] => 0 } }

    expect(delta(current, previous)).to eq([2, 4, 5])
  end

  it "ignores methods whose call count did not increase" do
    current = { lines: [1, 1], methods: { [Object, :x, 2, 2, 2, 17] => 1 } }

    expect(delta(current, current)).to eq([])
  end

  it "attributes a method first seen in the current snapshot when it was called" do
    current = { lines: [1, 1], methods: { [Object, :x, 2, 2, 2, 17] => 1 } }

    expect(delta(current, { lines: [1, 1] })).to eq([2])
  end
end
