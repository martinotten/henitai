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

  it "reads kill counts from hash-style history values with symbol keys" do
    tests = %w[spec/a_spec.rb spec/b_spec.rb spec/c_spec.rb]
    history = {
      "spec/b_spec.rb" => { kills: 10 },
      "spec/a_spec.rb" => { kills: 2 }
    }

    expect(described_class.new.sort(tests, nil, history)).to eq(
      %w[spec/b_spec.rb spec/a_spec.rb spec/c_spec.rb]
    )
  end

  it "reads kill counts from hash-style history values with string keys" do
    tests = %w[spec/a_spec.rb spec/b_spec.rb]
    history = {
      "spec/b_spec.rb" => { "kills" => 7 },
      "spec/a_spec.rb" => { "kills" => 1 }
    }

    expect(described_class.new.sort(tests, nil, history)).to eq(
      %w[spec/b_spec.rb spec/a_spec.rb]
    )
  end

  describe "runtime tiebreaker" do
    def timing_source_for(durations)
      -> { durations }
    end

    it "orders equal-history tests by ascending measured runtime" do
      tests = %w[spec/slow_spec.rb spec/fast_spec.rb spec/medium_spec.rb]
      prioritizer = described_class.new(
        timing_source: timing_source_for(
          "spec/slow_spec.rb" => 9.0,
          "spec/fast_spec.rb" => 0.1,
          "spec/medium_spec.rb" => 2.0
        )
      )

      expect(prioritizer.sort(tests, nil, nil)).to eq(
        %w[spec/fast_spec.rb spec/medium_spec.rb spec/slow_spec.rb]
      )
    end

    it "keeps kill history dominant over runtime" do
      tests = %w[spec/slow_spec.rb spec/fast_spec.rb]
      history = { "spec/slow_spec.rb" => 3 }
      prioritizer = described_class.new(
        timing_source: timing_source_for(
          "spec/slow_spec.rb" => 9.0,
          "spec/fast_spec.rb" => 0.1
        )
      )

      expect(prioritizer.sort(tests, nil, history)).to eq(tests)
    end

    it "sorts untimed tests after timed ones by original index" do
      tests = %w[spec/untimed_a_spec.rb spec/timed_spec.rb spec/untimed_b_spec.rb]
      prioritizer = described_class.new(
        timing_source: timing_source_for("spec/timed_spec.rb" => 1.0)
      )

      expect(prioritizer.sort(tests, nil, nil)).to eq(
        %w[spec/timed_spec.rb spec/untimed_a_spec.rb spec/untimed_b_spec.rb]
      )
    end

    it "matches absolute test paths against relative timing keys" do
      tests = %w[spec/slow_spec.rb spec/fast_spec.rb].map { |path| File.expand_path(path) }
      prioritizer = described_class.new(
        timing_source: timing_source_for(
          "spec/slow_spec.rb" => 9.0,
          "spec/fast_spec.rb" => 0.1
        )
      )

      expect(prioritizer.sort(tests, nil, nil)).to eq(tests.reverse)
    end

    it "falls back to the original order when the timing source is empty" do
      tests = %w[spec/a_spec.rb spec/b_spec.rb]
      prioritizer = described_class.new(timing_source: timing_source_for({}))

      expect(prioritizer.sort(tests, nil, nil)).to eq(tests)
    end
  end

  it "matches absolute test paths against relative history keys" do
    tests = %w[spec/a_spec.rb spec/b_spec.rb spec/c_spec.rb].map do |path|
      File.expand_path(path)
    end
    history = {
      "spec/b_spec.rb" => 5,
      "spec/a_spec.rb" => 1
    }

    expect(described_class.new.sort(tests, nil, history)).to eq(
      tests.values_at(1, 0, 2)
    )
  end
end
