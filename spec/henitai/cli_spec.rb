# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::CLI do
  def write_configuration(dir)
    path = File.join(dir, ".henitai.yml")
    File.write(
      path,
      <<~YAML
        integration:
          name: rspec
        jobs: 2
        mutation:
          operators: light
      YAML
    )
    path
  end

  def configuration_snapshot(config)
    {
      integration: config.integration,
      operators: config.operators,
      jobs: config.jobs
    }
  end

  it "applies CLI overrides after loading the YAML config" do
    Dir.mktmpdir do |dir|
      config_path = write_configuration(dir)
      captured_config = nil
      runner = instance_double(Henitai::Runner)
      result = instance_double(Henitai::Result, mutation_score: 100)

      allow(Henitai::Runner).to receive(:new) do |config:, **_kwargs|
        captured_config = config
        runner
      end
      allow(runner).to receive(:run).and_return(result)

      cli = described_class.new(
        [
          "run",
          "--config",
          config_path,
          "--use",
          "minitest",
          "--operators",
          "full",
          "--jobs",
          "4"
        ]
      )
      cli.define_singleton_method(:exit) { |_status = nil| nil }
      cli.run

      expect(configuration_snapshot(captured_config)).to eq(
        integration: "minitest",
        operators: :full,
        jobs: 4
      )
    end
  end
end
