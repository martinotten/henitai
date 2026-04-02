# frozen_string_literal: true

require "spec_helper"
require "henitai/configuration_validator"

RSpec.describe Henitai::ConfigurationValidator do
  describe ".validate!" do
    it "rejects a non-hash root configuration" do
      expect { described_class.validate!([]) }.to raise_error(
        Henitai::ConfigurationError,
        /configuration/
      )
    end
  end

  describe "sampling validation" do
    it "requires ratio to be paired with strategy" do
      expect do
        described_class.send(:validate_sampling, { ratio: 0.5 })
      end.to raise_error(
        Henitai::ConfigurationError,
        /mutation\.sampling/
      )
    end

    it "requires strategy to be paired with ratio" do
      expect do
        described_class.send(:validate_sampling, { strategy: "stratified" })
      end.to raise_error(
        Henitai::ConfigurationError,
        /mutation\.sampling/
      )
    end
  end

  describe "unknown key warnings" do
    it "includes the top-level key name" do
      expect do
        described_class.send(
          :warn_unknown_keys,
          { unknown_top_level: true },
          %i[integration]
        )
      end.to output("Unknown configuration key: unknown_top_level\n").to_stderr
    end

    it "includes the nested key path" do
      expect do
        described_class.send(
          :warn_unknown_keys,
          { unknown_flag: true },
          %i[operators],
          "mutation"
        )
      end.to output("Unknown configuration key: mutation.unknown_flag\n").to_stderr
    end
  end

  describe "string array validation" do
    it "describes a non-array value precisely" do
      expect do
        described_class.send(:validate_string_array, "lib", "includes")
      end.to raise_error(
        Henitai::ConfigurationError,
        /includes: expected Array<String>, got String/
      )
    end

    it "describes mixed array element types precisely" do
      expect do
        described_class.send(
          :validate_string_array,
          ["(send _ :puts _)", 1],
          "mutation.ignore_patterns"
        )
      end.to raise_error(
        Henitai::ConfigurationError,
        /mutation\.ignore_patterns: expected Array<String>, got Array<String, Integer>/
      )
    end
  end
end
