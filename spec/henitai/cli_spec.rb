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

  def build_runner(result:)
    runner = instance_double(Henitai::Runner)
    allow(runner).to receive(:run).and_return(result)
    runner
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

  it "prints the version string" do
    expect { described_class.new(["version"]).run }.to output(
      "#{Henitai::VERSION}\n"
    ).to_stdout
  end

  it "prints the help text for -h" do
    cli = described_class.new(["-h"])
    cli.define_singleton_method(:exit) { |_status = nil| nil }

    expect { cli.run }.to output(/Hen'i-tai 変異体/).to_stdout
  end

  it "prints the help text for --help" do
    cli = described_class.new(["--help"])
    cli.define_singleton_method(:exit) { |_status = nil| nil }

    expect { cli.run }.to output(/Hen'i-tai 変異体/).to_stdout
  end

  it "prints the help text when no command is given" do
    expect { described_class.new([]).run }.to output(/Hen'i-tai 変異体/).to_stdout
  end

  it "warns and exits for unknown commands" do
    cli = described_class.new(["bogus"])
    exit_status = nil
    cli.define_singleton_method(:exit) { |status = nil| exit_status = status }

    cli.run

    expect(exit_status).to eq(1)
  end

  it "passes subject patterns through" do
    Dir.mktmpdir do |dir|
      config_path = write_configuration(dir)
      captured_subjects = nil
      result = instance_double(Henitai::Result, mutation_score: 0)
      runner = build_runner(result:)

      allow(Henitai::Runner).to receive(:new) do |**kwargs|
        captured_subjects = kwargs[:subjects]
        runner
      end

      cli = described_class.new(
        [
          "run",
          "--config",
          config_path,
          "Foo#bar"
        ]
      )
      cli.define_singleton_method(:exit) { |_status = nil| nil }
      cli.run

      expect(captured_subjects.map(&:expression)).to eq(["Foo#bar"])
    end
  end

  it "exits non-zero for a low score" do
    Dir.mktmpdir do |dir|
      config_path = write_configuration(dir)
      exit_status = nil
      result = instance_double(Henitai::Result, mutation_score: 0)
      runner = build_runner(result:)

      allow(Henitai::Runner).to receive(:new) do |**_kwargs|
        runner
      end

      cli = described_class.new(
        [
          "run",
          "--config",
          config_path,
          "Foo#bar"
        ]
      )
      cli.define_singleton_method(:exit) { |status = nil| exit_status = status }
      cli.run

      expect(exit_status).to eq(1)
    end
  end

  it "omits unset override values when loading the configuration" do
    Dir.mktmpdir do |dir|
      config_path = write_configuration(dir)
      captured_overrides = nil
      runner = build_runner(result: instance_double(Henitai::Result, mutation_score: 100))
      config = instance_double(Henitai::Configuration, thresholds: { low: 60 })

      allow(Henitai::Configuration).to receive(:load) do |**kwargs|
        captured_overrides = kwargs[:overrides]
        config
      end
      allow(Henitai::Runner).to receive(:new).and_return(runner)

      cli = described_class.new(
        [
          "run",
          "--config",
          config_path,
          "--use",
          "minitest",
          "--operators",
          "full"
        ]
      )
      cli.define_singleton_method(:exit) { |_status = nil| nil }
      cli.run

      expect(captured_overrides).to eq(
        integration: "minitest",
        mutation: {
          operators: "full"
        }
      )
    end
  end
end
