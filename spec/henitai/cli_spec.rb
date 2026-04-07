# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "stringio"

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
      jobs: config.jobs,
      all_logs: config.all_logs
    }
  end

  def build_runner(result:)
    runner = instance_double(Henitai::Runner)
    allow(runner).to receive(:run).and_return(result)
    runner
  end

  # L125 — OptionParser-Banner ("Usage: henitai run …")
  # L137, L167, L174 — Optionsbeschreibungen werden nie auf Inhalt geprüft
  describe "run --help output" do
    subject(:help_output) do
      cli = described_class.new(["run", "--help"])
      capture_stdout { cli.run }
    end

    it "prints the run usage banner" do
      expect(help_output).to match(/Usage: henitai run/)
    end

    it "documents the --since option" do
      expect(help_output).to match(/--since/)
    end

    it "documents the -h / --help flag" do
      expect(help_output).to match(/-h, --help/)
    end

    it "documents the -v / --version flag" do
      expect(help_output).to match(/-v, --version/)
    end

    it "documents the --all-logs flag" do
      expect(help_output).to match(/--all-logs/)
    end
  end

  def capture_stdout
    original_stdout = $stdout
    stdout = StringIO.new
    $stdout = stdout
    yield
    stdout.string
  ensure
    $stdout = original_stdout
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
          "4",
          "--all-logs"
        ]
      )
      cli.define_singleton_method(:exit) { |_status = nil| nil }
      cli.run

      expect(configuration_snapshot(captured_config)).to eq(
        integration: "minitest",
        operators: :full,
        jobs: 4,
        all_logs: true
      )
    end
  end

  it "prints the version string" do
    expect { described_class.new(["version"]).run }.to output(
      "#{Henitai::VERSION}\n"
    ).to_stdout
  end

  it "does not continue the run pipeline after run -v" do
    cli = described_class.new(["run", "-v"])
    allow(Henitai::Runner).to receive(:new).and_raise(
      "run pipeline should not continue after version"
    )
    cli.define_singleton_method(:exit) { |_status = nil| nil }

    expect { cli.run }.to output("#{Henitai::VERSION}\n").to_stdout
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

  # L181 — VERSION-Interpolation in help_text muss tatsächlich geprüft werden
  it "includes the version number in the help text" do
    expect { described_class.new([]).run }.to output(
      /Hen'i-tai 変異体 #{Regexp.escape(Henitai::VERSION)}/
    ).to_stdout
  end

  it "warns and exits for unknown commands" do
    cli = described_class.new(["bogus"])
    exit_status = nil
    cli.define_singleton_method(:exit) { |status = nil| exit_status = status }

    cli.run

    expect(exit_status).to eq(1)
  end

  # L73 — Warntext muss den Command-Namen enthalten (StringLiteral-Interpolation)
  it "includes the unknown command name in the warning" do
    cli = described_class.new(["bogus"])
    cli.define_singleton_method(:exit) { |_status = nil| nil }
    allow(cli).to receive(:warn)

    cli.run

    expect(cli).to have_received(:warn).with("Unknown command: bogus")
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

  it "exits zero for a high score" do
    Dir.mktmpdir do |dir|
      config_path = write_configuration(dir)
      exit_status = nil
      result = instance_double(Henitai::Result, mutation_score: 100)
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

      expect(exit_status).to eq(0)
    end
  end

  it "exits with a framework error code when the runner fails" do
    Dir.mktmpdir do |dir|
      config_path = write_configuration(dir)
      runner = instance_double(Henitai::Runner)

      allow(Henitai::Runner).to receive(:new).and_return(runner)
      allow(runner).to receive(:run).and_raise(Henitai::ConfigurationError, "boom")

      cli = described_class.new(["run", "--config", config_path])
      cli.define_singleton_method(:exit) do |status = nil|
        raise "expected exit status 2, got #{status.inspect}" unless status == 2
      end
      allow(cli).to receive(:warn)

      cli.run

      expect(cli).to have_received(:warn).with("Henitai::ConfigurationError: boom")
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

  it "creates a default configuration file during init" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        cli = described_class.new(["init"])
        allow($stdin).to receive_messages(tty?: false, gets: nil)

        expect { cli.run }.to output(/Created \.henitai\.yml/).to_stdout
      end
    end
  end

  it "includes the default integration block during init" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        cli = described_class.new(["init"])
        allow($stdin).to receive_messages(tty?: false, gets: nil)

        cli.run

        expect(File.read(".henitai.yml")).to include("integration:\n  name: rspec")
      end
    end
  end

  it "can skip the explicit integration block during init" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        cli = described_class.new(["init"])
        allow($stdin).to receive_messages(tty?: true, gets: "n\n")

        cli.run

        expect(File.read(".henitai.yml")).not_to include("integration:")
      end
    end
  end

  it "writes the exact default integration block during init" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        cli = described_class.new(["init"])
        allow($stdin).to receive_messages(tty?: true, gets: "y\n")

        cli.run

        expect(File.read(".henitai.yml")).to eq(<<~YAML)
          # yaml-language-server: $schema=./assets/schema/henitai.schema.json
          includes:
            - lib
          mutation:
            operators: light
            timeout: 10.0
            max_mutants_per_line: 1
            max_flaky_retries: 3
            sampling:
              ratio: 0.05
              strategy: stratified
          reports_dir: reports
          thresholds:
            high: 80
            low: 60
          integration:
            name: rspec
        YAML
      end
    end
  end

  # L269 — Prompt-String muss tatsächlich ausgegeben werden (StringLiteral)
  it "prints the RSpec prompt text when stdin is a tty" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        cli = described_class.new(["init"])
        allow($stdin).to receive_messages(tty?: true, gets: "y\n")

        expect { cli.run }.to output(%r{Use the default RSpec integration\? \[Y/n\]}).to_stdout
      end
    end
  end

  # L271 — LogicalOperator: || → and (Präzedenz-Bug)
  # Bei response = "yes": Original gibt true zurück (Integration einbinden),
  # Mutation gibt false (weil `(false || false) and true` = false).
  it "includes the integration block when the user types 'yes'" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        cli = described_class.new(["init"])
        allow($stdin).to receive_messages(tty?: true, gets: "yes\n")

        cli.run

        expect(File.read(".henitai.yml")).to include("integration:\n  name: rspec")
      end
    end
  end

  # L271 — Sicherstellen dass ein leerer Enter (response.empty?) auch einbindet
  it "includes the integration block when the user presses enter without input" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        cli = described_class.new(["init"])
        allow($stdin).to receive_messages(tty?: true, gets: "\n")

        cli.run

        expect(File.read(".henitai.yml")).to include("integration:\n  name: rspec")
      end
    end
  end

  # L275 — integration_block ohne trailing Double-Newline (.chomp)
  it "does not produce a trailing blank line in the generated config" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        cli = described_class.new(["init"])
        allow($stdin).to receive_messages(tty?: false, gets: nil)

        cli.run

        expect(File.read(".henitai.yml")).not_to end_with("\n\n")
      end
    end
  end

  it "creates the requested configuration file during init" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        cli = described_class.new(["init", "custom.yml"])
        allow($stdin).to receive_messages(tty?: false, gets: nil)
        cli.define_singleton_method(:exit) { |_status = nil| nil }

        cli.run

        expect(File).to exist("custom.yml")
      end
    end
  end

  it "prints a warning when init receives unexpected arguments" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        cli = described_class.new(["init", "custom.yml", "extra"])
        allow($stdin).to receive_messages(tty?: false, gets: nil)
        cli.define_singleton_method(:exit) { |_status = nil| nil }
        allow(cli).to receive(:warn)

        cli.run

        expect(cli).to have_received(:warn).with("Unexpected arguments: extra")
      end
    end
  end

  it "exits non-zero when init receives unexpected arguments" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        cli = described_class.new(["init", "custom.yml", "extra"])
        exit_status = nil
        allow($stdin).to receive_messages(tty?: false, gets: nil)
        cli.define_singleton_method(:exit) { |status = nil| exit_status = status }

        cli.run

        expect(exit_status).to eq(1)
      end
    end
  end

  it "lists operators with descriptions and examples" do
    expect { described_class.new(%w[operator list]).run }.to output(
      /ArithmeticOperator.*a \+ b -> a - b/m
    ).to_stdout
  end

  # L295 — "Available operators"-Header muss in der Ausgabe erscheinen (StringLiteral)
  it "prints the 'Available operators' header" do
    expect { described_class.new(%w[operator list]).run }.to output(
      /Available operators/
    ).to_stdout
  end

  it "prints the exact operator help text for help" do
    expect { described_class.new(%w[operator --help]).run }.to output(<<~HELP).to_stdout
      Hen'i-tai operator commands

      Usage:
        henitai operator list

      Run `henitai operator list` to see all built-in operators.
    HELP
  end

  # L299 — "\n"-Separator zwischen Sektionen (join("\n") → join(""))
  it "separates the Light and Full operator sections with a newline" do
    expect { described_class.new(%w[operator list]).run }.to output(
      /Light set\n.*Full set/m
    ).to_stdout
  end

  it "warns and exits when operator metadata is missing" do
    stub_const(
      "Henitai::Operator::FULL_SET",
      Henitai::Operator::FULL_SET + ["MissingOperator"]
    )

    cli = described_class.new(%w[operator list])
    exit_status = nil
    cli.define_singleton_method(:exit) { |status = nil| exit_status = status }
    allow(cli).to receive(:warn)

    aggregate_failures do
      cli.run
      expect(cli).to have_received(:warn).with("Missing operator metadata for: MissingOperator")
      expect(exit_status).to eq(1)
    end
  end

  it "prints a warning for unknown operator subcommands" do
    cli = described_class.new(%w[operator bogus])
    cli.define_singleton_method(:exit) { |_status = nil| nil }
    allow(cli).to receive(:warn)

    cli.run

    expect(cli).to have_received(:warn).with("Unknown operator command: bogus")
  end

  it "exits non-zero for unknown operator subcommands" do
    cli = described_class.new(%w[operator bogus])
    exit_status = nil
    cli.define_singleton_method(:exit) { |status = nil| exit_status = status }

    cli.run

    expect(exit_status).to eq(1)
  end

  # L282 — operator_help_text-Inhalt: kein Test für operator ohne Subcommand / mit -h
  it "prints operator usage when 'operator' is called without a subcommand" do
    expect { described_class.new(["operator"]).run }.to output(
      /henitai operator list/
    ).to_stdout
  end

  it "prints operator usage for 'operator -h'" do
    cli = described_class.new(["operator", "-h"])
    cli.define_singleton_method(:exit) { |_status = nil| nil }

    expect { cli.run }.to output(/henitai operator list/).to_stdout
  end

  # L57 NoCoverage — CLI.start() wird nie direkt aufgerufen
  it "delegates to run via the class-level start method" do
    expect { described_class.start(["version"]) }.to output(
      "#{Henitai::VERSION}\n"
    ).to_stdout
  end

  # L318 NoCoverage — fallback_operator_metadata für unbekannte Operatoren
  it "uses fallback metadata text for operators missing from OPERATOR_METADATA" do
    cli = described_class.new(%w[operator list])
    allow(cli).to receive_messages(operator_metadata: {}, validate_operator_metadata!: nil)

    expect { cli.run }.to output(/No metadata available/).to_stdout
  end
end
