# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::Configuration do
  def load_configuration(yaml)
    Dir.mktmpdir do |dir|
      path = File.join(dir, ".henitai.yml")
      File.write(path, yaml)
      described_class.load(path:)
    end
  end

  def configuration_snapshot(config)
    {
      timeout: config.timeout,
      coverage_criteria: config.coverage_criteria,
      thresholds: config.thresholds
    }
  end

  def expected_snapshot
    {
      timeout: 12.5,
      coverage_criteria: {
        test_result: false,
        timeout: false,
        process_abort: false
      },
      thresholds: {
        high: 90,
        low: 60
      }
    }
  end

  it "merges partial nested config hashes with defaults" do
    expect(configuration_snapshot(load_configuration(<<~YAML))).to eq(expected_snapshot)
      mutation:
        timeout: 12.5
      coverage_criteria:
        test_result: false
      thresholds:
        high: 90
    YAML
  end
end
