# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::SurvivorSelector do
  def build_mutant_double(stable_id)
    instance_double(Henitai::Mutant, stable_id:)
  end

  describe "#select" do
    it "returns only mutants whose stable_id is in the survivor set" do
      match    = build_mutant_double("aaa")
      no_match = build_mutant_double("bbb")
      selector = described_class.new(survivor_ids: ["aaa"])
      expect(selector.select([match, no_match])).to eq([match])
    end

    it "returns an empty array when no mutants match" do
      mutant   = build_mutant_double("aaa")
      selector = described_class.new(survivor_ids: ["zzz"])
      expect(selector.select([mutant])).to be_empty
    end

    it "returns an empty array when survivor_ids is empty" do
      mutant   = build_mutant_double("aaa")
      selector = described_class.new(survivor_ids: [])
      expect(selector.select([mutant])).to be_empty
    end
  end

  describe "#unmatched_ids" do
    it "tracks survivor ids that had no corresponding current mutant" do
      mutant   = build_mutant_double("aaa")
      selector = described_class.new(survivor_ids: %w[aaa bbb ccc])
      selector.select([mutant])
      expect(selector.unmatched_ids).to contain_exactly("bbb", "ccc")
    end

    it "is empty when all survivors are matched" do
      mutants  = [build_mutant_double("aaa"), build_mutant_double("bbb")]
      selector = described_class.new(survivor_ids: %w[aaa bbb])
      selector.select(mutants)
      expect(selector.unmatched_ids).to be_empty
    end
  end

  describe "#drift_warning?" do
    it "returns true when more than 50% of survivor ids are unmatched" do
      mutant   = build_mutant_double("aaa")
      selector = described_class.new(survivor_ids: %w[aaa bbb ccc])
      selector.select([mutant])
      expect(selector.drift_warning?).to be(true)
    end

    it "returns false when fewer than half are unmatched" do
      mutants  = [build_mutant_double("aaa"), build_mutant_double("bbb")]
      selector = described_class.new(survivor_ids: %w[aaa bbb ccc])
      selector.select(mutants)
      expect(selector.drift_warning?).to be(false)
    end

    it "returns false when survivor_ids is empty" do
      selector = described_class.new(survivor_ids: [])
      selector.select([])
      expect(selector.drift_warning?).to be(false)
    end
  end
end
