# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "stringio"

RSpec.describe Henitai::CLI do
  around do |example|
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) { example.run }
    end
  end

  def write_configuration(dir, reports_dir: "reports")
    path = File.join(dir, ".henitai.yml")
    File.write(
      path,
      <<~YAML
        integration:
          name: rspec
        jobs: 2
        reports_dir: #{reports_dir}
        mutation:
          operators: light
      YAML
    )
    path
  end

  def write_minimal_report_artifacts(reports_dir)
    paths = Henitai::CLI::REPORT_CLEANUP_PATHS.map do |relative_path|
      File.join(reports_dir, *relative_path)
    end

    paths.each do |path|
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "stale")
    end

    paths
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

  def write_survivors_from_fixture(report_dir:, session_id:)
    report_path = File.join(report_dir, "mutation-report.json")
    canonical_report = JSON.generate("schemaVersion" => "1.0", "sessionId" => session_id, "files" => {})

    File.write(report_path, canonical_report)

    sessions_dir = File.join(report_dir, "sessions", session_id)
    FileUtils.mkdir_p(sessions_dir)

    File.write(File.join(sessions_dir, "activation-recipes.json"), JSON.generate({}))
    snapshot_path = File.join(sessions_dir, "mutation-report.json")
    File.write(snapshot_path, canonical_report)
    [report_path, snapshot_path]
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

    it "prints the exact run help text" do
      expect(help_output).to eq(<<~HELP)
        Usage: henitai run [options] [SUBJECT_PATTERN...]
                --since GIT_REF              Only mutate subjects changed since GIT_REF
                --use INTEGRATION            Test framework integration (rspec)
                --config PATH                Path to .henitai.yml
                --operators SET              Operator set: light | full
                --jobs N                     Number of parallel workers (default: 1)
                --all-logs, --verbose        Print all captured child logs
                --survivors-from PATH        Re-run only survivors from a prior report (partial rerun; threshold checks are skipped; dirty worktrees are included)
                --fail-on-survivors          Exit 1 for partial reruns when any survivors remain (otherwise exits 0)
            -h, --help                       Show this help
            -v, --version                    Show version
      HELP
    end

    it "documents the --survivors-from flag" do
      expect(help_output).to match(/--survivors-from/)
    end

    it "documents the --fail-on-survivors flag" do
      expect(help_output).to match(/--fail-on-survivors/)
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

  it "runs in an isolated working directory" do
    repo_root = File.expand_path("../..", __dir__)

    expect(Dir.pwd).not_to eq(repo_root)
  end

  it "applies CLI overrides after loading the YAML config" do
    Dir.mktmpdir do |dir|
      config_path = write_configuration(dir)
      captured_config = nil
      runner = instance_double(Henitai::Runner)
      result = instance_double(Henitai::Result, mutation_score: 100, partial_rerun?: false)

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

  it "removes the minimal generated report artifacts with clean" do
    Dir.mktmpdir do |dir|
      reports_dir = File.join(dir, "custom-reports")
      config_path = write_configuration(dir, reports_dir:)
      cleanup_paths = write_minimal_report_artifacts(reports_dir)
      sentinel_path = File.join(reports_dir, "mutation-history.json")

      FileUtils.mkdir_p(reports_dir)
      File.write(sentinel_path, "keep")

      aggregate_failures do
        expect do
          described_class.new(["clean", "--config", config_path]).run
        end.to output(/Removed 6 generated report artifacts/).to_stdout
        expect(cleanup_paths.all? { |path| !File.exist?(path) }).to be(true)
        expect(File).to exist(sentinel_path)
      end
    end
  end

  it "counts only the report artifacts that already exist" do
    Dir.mktmpdir do |dir|
      reports_dir = File.join(dir, "custom-reports")
      config_path = write_configuration(dir, reports_dir:)
      existing_path = File.join(reports_dir, "mutation-logs", "baseline.log")

      FileUtils.mkdir_p(File.dirname(existing_path))
      File.write(existing_path, "stale")

      aggregate_failures do
        expect do
          described_class.new(["clean", "--config", config_path]).run
        end.to output(/Removed 1 generated report artifact/).to_stdout
        expect(File).not_to exist(existing_path)
      end
    end
  end

  it "prints clean help without removing any artifacts" do
    Dir.mktmpdir do |dir|
      reports_dir = File.join(dir, "custom-reports")
      config_path = write_configuration(dir, reports_dir:)
      cleanup_paths = write_minimal_report_artifacts(reports_dir)

      aggregate_failures do
        expect do
          described_class.new(["clean", "--config", config_path, "--help"]).run
        end.to output(/Usage: henitai clean/).to_stdout
        expect(cleanup_paths.all? { |path| File.exist?(path) }).to be(true)
      end
    end
  end

  it "exits with a framework error code when clean fails" do
    cli = described_class.new(["clean", "--config", ".henitai.yml"])
    cli.define_singleton_method(:exit) do |status = nil|
      raise "expected exit status 2, got #{status.inspect}" unless status == 2
    end
    allow(cli).to receive(:warn)
    allow(Henitai::Configuration).to receive(:load).and_raise(Henitai::ConfigurationError, "boom")

    cli.run

    expect(cli).to have_received(:warn).with("Henitai::ConfigurationError: boom")
  end

  it "does not clean report artifacts automatically during run" do
    Dir.mktmpdir do |dir|
      reports_dir = File.join(dir, "custom-reports")
      config_path = write_configuration(dir, reports_dir:)
      cleanup_paths = write_minimal_report_artifacts(reports_dir)
      sentinel_path = File.join(reports_dir, "mutation-history.json")
      runner = build_runner(result: instance_double(Henitai::Result, mutation_score: 100, partial_rerun?: false))
      runner_instantiated = false

      FileUtils.mkdir_p(reports_dir)
      File.write(sentinel_path, "keep")

      allow(Henitai::Runner).to receive(:new) do |**_kwargs|
        runner_instantiated = true
        runner
      end

      cli = described_class.new(["run", "--config", config_path, "Foo#bar"])
      cli.define_singleton_method(:exit) { |_status = nil| nil }
      cli.run

      aggregate_failures do
        expect(runner_instantiated).to be(true)
        expect(cleanup_paths.all? { |path| File.exist?(path) }).to be(true)
        expect(File).to exist(sentinel_path)
      end
    end
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

  it "prints the exact top-level help text when no command is given" do
    expect { described_class.new([]).run }.to output(<<~HELP).to_stdout
      Hen'i-tai 変異体 #{Henitai::VERSION} — Ruby 4 Mutation Testing

      Usage:
        henitai run [options] [SUBJECT_PATTERN...]
        henitai clean [options]
        henitai version
        henitai init [PATH]
        henitai operator list

      Examples:
        bundle exec henitai run
        bundle exec henitai run --since origin/main
        bundle exec henitai run 'Foo::Bar#my_method'
        bundle exec henitai run 'MyNamespace*' --operators full
        bundle exec henitai run --survivors-from reports/mutation-report.json
        bundle exec henitai clean
        bundle exec henitai init
        bundle exec henitai operator list

      Run `henitai run --help` for full option list.
    HELP
  end

  it "documents the clean command in the top-level help" do
    expect { described_class.new([]).run }.to output(/henitai clean \[options\]/).to_stdout
  end

  # L181 — VERSION-Interpolation in help_text muss tatsächlich geprüft werden
  it "includes the version number in the help text" do
    expect { described_class.new([]).run }.to output(
      /Hen'i-tai 変異体 #{Regexp.escape(Henitai::VERSION)}/
    ).to_stdout
  end

  it "passes no subject patterns to the runner when none are given" do
    Dir.mktmpdir do |dir|
      config_path = write_configuration(dir)
      captured_subjects = :not_set
      result = instance_double(Henitai::Result, mutation_score: 100, partial_rerun?: false)
      runner = build_runner(result:)

      allow(Henitai::Runner).to receive(:new) do |**kwargs|
        captured_subjects = kwargs[:subjects]
        runner
      end

      cli = described_class.new(["run", "--config", config_path])
      cli.define_singleton_method(:exit) { |_status = nil| nil }
      cli.run

      expect(captured_subjects).to be_nil
    end
  end

  it "passes nil survivors_from to the runner when none are given" do
    Dir.mktmpdir do |dir|
      config_path = write_configuration(dir)
      captured_survivors_from = :not_set
      result = instance_double(Henitai::Result, mutation_score: 100, partial_rerun?: false)
      runner = build_runner(result:)

      allow(Henitai::Runner).to receive(:new) do |**kwargs|
        captured_survivors_from = kwargs[:survivors_from]
        runner
      end

      cli = described_class.new(["run", "--config", config_path])
      cli.define_singleton_method(:exit) { |_status = nil| nil }
      cli.run

      expect(captured_survivors_from).to be_nil
    end
  end

  it "does not warn when survivors_from is omitted" do
    Dir.mktmpdir do |dir|
      config_path = write_configuration(dir)
      result = instance_double(Henitai::Result, mutation_score: 100, partial_rerun?: false)
      runner = build_runner(result:)

      allow(Henitai::Runner).to receive(:new).and_return(runner)

      cli = described_class.new(["run", "--config", config_path])
      cli.define_singleton_method(:exit) { |_status = nil| nil }
      allow(cli).to receive(:warn)
      cli.run

      expect(cli).not_to have_received(:warn)
    end
  end

  it "keeps an already snapshot-shaped survivors-from path unchanged" do
    Dir.mktmpdir do |dir|
      config_path = write_configuration(dir)
      report_dir = File.join(dir, "reports")
      FileUtils.mkdir_p(report_dir)
      embedded_session_id = "fedcba98-7654-3210-fedc-ba9876543210"
      snapshot_path = File.join(report_dir, "sessions", embedded_session_id, "mutation-report.json")
      FileUtils.mkdir_p(File.dirname(snapshot_path))
      File.write(snapshot_path, "{not-json")
      parent_dir = File.dirname(snapshot_path, 2)
      sessions_marker = Object.new
      sessions_marker.define_singleton_method(:==) { |other| other == "sessions" }
      sessions_marker.define_singleton_method(:>=) { |_other| false }
      sessions_marker.define_singleton_method(:>) { |_other| false }
      captured_survivors_from = :not_set
      result = instance_double(Henitai::Result, mutation_score: 100, partial_rerun?: true)
      runner = build_runner(result:)

      allow(JSON).to receive(:parse).and_raise(ArgumentError, "boom")
      allow(File).to receive(:basename).and_wrap_original do |original, path|
        path == parent_dir ? sessions_marker : original.call(path)
      end
      cli = described_class.new(["run", "--config", config_path, "--survivors-from", snapshot_path])
      cli.define_singleton_method(:exit) { |_status = nil| nil }
      allow(cli).to receive(:warn)
      allow(Henitai::Runner).to receive(:new) do |**kwargs|
        captured_survivors_from = kwargs[:survivors_from]
        runner
      end

      cli.run

      expect(captured_survivors_from).to eq(snapshot_path)
    end
  end

  it "does not warn about resolving an already snapshot-shaped survivors-from path" do
    Dir.mktmpdir do |dir|
      config_path = write_configuration(dir)
      report_dir = File.join(dir, "reports")
      FileUtils.mkdir_p(report_dir)
      embedded_session_id = "fedcba98-7654-3210-fedc-ba9876543210"
      snapshot_path = File.join(report_dir, "sessions", embedded_session_id, "mutation-report.json")
      FileUtils.mkdir_p(File.dirname(snapshot_path))
      File.write(snapshot_path, "{not-json")
      parent_dir = File.dirname(snapshot_path, 2)
      sessions_marker = Object.new
      sessions_marker.define_singleton_method(:==) { |other| other == "sessions" }
      sessions_marker.define_singleton_method(:>=) { |_other| false }
      sessions_marker.define_singleton_method(:>) { |_other| false }
      result = instance_double(Henitai::Result, mutation_score: 100, partial_rerun?: true)
      runner = build_runner(result:)

      allow(JSON).to receive(:parse).and_raise(ArgumentError, "boom")
      allow(File).to receive(:basename).and_wrap_original do |original, path|
        path == parent_dir ? sessions_marker : original.call(path)
      end
      allow(Henitai::Runner).to receive(:new).and_return(runner)

      cli = described_class.new(["run", "--config", config_path, "--survivors-from", snapshot_path])
      cli.define_singleton_method(:exit) { |_status = nil| nil }
      allow(cli).to receive(:warn)

      cli.run

      expect(cli).not_to have_received(:warn).with(/could not resolve survivors-from/)
    end
  end

  it "falls back to the original survivors-from path when the report has no session id" do
    Dir.mktmpdir do |dir|
      config_path = write_configuration(dir)
      report_path = File.join(dir, "mutation-report.json")
      File.write(report_path, JSON.generate("schemaVersion" => "1.0", "files" => {}))
      captured_survivors_from = :not_set
      result = instance_double(Henitai::Result, mutation_score: 100, partial_rerun?: true)
      runner = build_runner(result:)

      allow(Henitai::Runner).to receive(:new) do |**kwargs|
        captured_survivors_from = kwargs[:survivors_from]
        runner
      end

      cli = described_class.new(["run", "--config", config_path, "--survivors-from", report_path])
      cli.define_singleton_method(:exit) { |_status = nil| nil }
      cli.run

      expect(captured_survivors_from).to eq(report_path)
    end
  end

  it "falls back to the original survivors-from path when snapshot artifacts are missing" do
    Dir.mktmpdir do |dir|
      config_path = write_configuration(dir)
      report_dir = File.join(dir, "reports")
      FileUtils.mkdir_p(report_dir)
      report_path, snapshot_path = write_survivors_from_fixture(
        report_dir: report_dir,
        session_id: "01234567-89ab-cdef-0123-456789abcdef"
      )
      FileUtils.rm_f(snapshot_path)
      captured_survivors_from = :not_set
      result = instance_double(Henitai::Result, mutation_score: 100, partial_rerun?: true)
      runner = build_runner(result:)

      allow(Henitai::Runner).to receive(:new) do |**kwargs|
        captured_survivors_from = kwargs[:survivors_from]
        runner
      end

      cli = described_class.new(["run", "--config", config_path, "--survivors-from", report_path])
      cli.define_singleton_method(:exit) { |_status = nil| nil }
      cli.run

      expect(captured_survivors_from).to eq(report_path)
    end
  end

  it "falls back to the original survivors-from path when activation recipes are missing" do
    Dir.mktmpdir do |dir|
      config_path = write_configuration(dir)
      report_dir = File.join(dir, "reports")
      FileUtils.mkdir_p(report_dir)
      report_path = File.join(report_dir, "mutation-report.json")
      session_id = "01234567-89ab-cdef-0123-456789abcdef"
      snapshot_path = File.join(report_dir, "sessions", session_id, "mutation-report.json")

      File.write(report_path, JSON.generate("schemaVersion" => "1.0", "sessionId" => session_id, "files" => {}))
      FileUtils.mkdir_p(File.dirname(snapshot_path))
      File.write(snapshot_path, JSON.generate("schemaVersion" => "1.0", "sessionId" => session_id, "files" => {}))

      captured_survivors_from = :not_set
      result = instance_double(Henitai::Result, mutation_score: 100, partial_rerun?: true)
      runner = build_runner(result:)

      allow(Henitai::Runner).to receive(:new) do |**kwargs|
        captured_survivors_from = kwargs[:survivors_from]
        runner
      end

      cli = described_class.new(["run", "--config", config_path, "--survivors-from", report_path])
      cli.define_singleton_method(:exit) { |_status = nil| nil }
      cli.run

      expect(captured_survivors_from).to eq(report_path)
    end
  end

  it "prints the no-artifacts clean summary when nothing is removed" do
    Dir.mktmpdir do |dir|
      config_path = write_configuration(dir)

      expect do
        described_class.new(["clean", "--config", config_path]).run
      end.to output("No generated report artifacts to clean\n").to_stdout
    end
  end

  it "prints the singular clean summary when one artifact is removed" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        config_path = write_configuration(dir)
        reports_dir = File.join(dir, "reports")
        FileUtils.mkdir_p(reports_dir)
        artifact_path = File.join(reports_dir, *Henitai::CLI::REPORT_CLEANUP_PATHS.first)
        FileUtils.mkdir_p(File.dirname(artifact_path))
        File.write(artifact_path, "stale")

        expect do
          described_class.new(["clean", "--config", config_path]).run
        end.to output("Removed 1 generated report artifact\n").to_stdout
      end
    end
  end

  it "prints the plural clean summary when multiple artifacts are removed" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        config_path = write_configuration(dir)
        reports_dir = File.join(dir, "reports")
        FileUtils.mkdir_p(reports_dir)

        Henitai::CLI::REPORT_CLEANUP_PATHS.first(2).each do |relative_path|
          artifact_path = File.join(reports_dir, *relative_path)
          FileUtils.mkdir_p(File.dirname(artifact_path))
          File.write(artifact_path, "stale")
        end

        expect do
          described_class.new(["clean", "--config", config_path]).run
        end.to output("Removed 2 generated report artifacts\n").to_stdout
      end
    end
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
      result = instance_double(Henitai::Result, mutation_score: 0, partial_rerun?: false)
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
      result = instance_double(Henitai::Result, mutation_score: 0, partial_rerun?: false)
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
      result = instance_double(Henitai::Result, mutation_score: 100, partial_rerun?: false)
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

  it "exits zero when there are no valid mutants to evaluate" do
    Dir.mktmpdir do |dir|
      config_path = write_configuration(dir)
      exit_status = nil
      result = instance_double(Henitai::Result, mutation_score: nil, partial_rerun?: false)
      runner = build_runner(result:)

      allow(Henitai::Runner).to receive(:new) { |**_kwargs| runner }

      cli = described_class.new(["run", "--config", config_path, "Foo#bar"])
      cli.define_singleton_method(:exit) { |status = nil| exit_status = status }
      cli.run

      expect(exit_status).to eq(0)
    end
  end

  it "exits zero when the score matches the low threshold" do
    Dir.mktmpdir do |dir|
      config_path = write_configuration(dir)
      exit_status = nil
      result = instance_double(Henitai::Result, mutation_score: 60, partial_rerun?: false)
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

  it "treats results without partial_rerun? as a normal run" do
    Dir.mktmpdir do |dir|
      config_path = write_configuration(dir)
      exit_status = nil
      result = Struct.new(:mutation_score).new(100)
      runner = build_runner(result:)

      allow(Henitai::Runner).to receive(:new) do |**_kwargs|
        runner
      end

      cli = described_class.new(["run", "--config", config_path])
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
      runner = build_runner(result: instance_double(Henitai::Result, mutation_score: 100, partial_rerun?: false))
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

        expect { cli.run }.to output("Created .henitai.yml\n").to_stdout
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

  it "does not include the integration block when the user types no" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        cli = described_class.new(["init"])
        allow($stdin).to receive_messages(tty?: true, gets: "no\n")

        cli.run

        expect(File.read(".henitai.yml")).not_to include("integration:\n  name: rspec")
      end
    end
  end

  it "includes the integration block when stdin reaches EOF" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        cli = described_class.new(["init"])
        allow($stdin).to receive_messages(tty?: true, gets: nil)

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

    expect { cli.run }.to output(%r{No metadata available \(n/a\)}).to_stdout
  end

  it "warns when multiple operators are missing metadata" do
    stub_const(
      "Henitai::Operator::FULL_SET",
      Henitai::Operator::FULL_SET + %w[MissingOperatorA MissingOperatorB]
    )

    cli = described_class.new(%w[operator list])
    cli.define_singleton_method(:exit) { |_status = nil| nil }
    allow(cli).to receive(:warn)

    cli.run

    expect(cli).to have_received(:warn).with(
      "Missing operator metadata for: MissingOperatorA, MissingOperatorB"
    )
  end

  it "exits non-zero when multiple operators are missing metadata" do
    stub_const(
      "Henitai::Operator::FULL_SET",
      Henitai::Operator::FULL_SET + %w[MissingOperatorA MissingOperatorB]
    )

    cli = described_class.new(%w[operator list])
    exit_status = nil
    cli.define_singleton_method(:exit) { |status = nil| exit_status = status }
    allow(cli).to receive(:warn)

    cli.run

    expect(exit_status).to eq(1)
  end

  it "documents the --survivors-from option" do
    cli = described_class.new(["run", "--help"])
    expect { cli.run }.to output(/--survivors-from/).to_stdout
  end

  it "passes survivors_from to the runner" do
    Dir.mktmpdir do |dir|
      config_path = write_configuration(dir)
      report_dir = File.join(dir, "reports")
      FileUtils.mkdir_p(report_dir)

      session_id = "01234567-89ab-cdef-0123-456789abcdef"
      report_path, expected_snapshot_path = write_survivors_from_fixture(
        report_dir: report_dir,
        session_id: session_id
      )

      captured_survivors_from = :not_set
      result = instance_double(Henitai::Result, mutation_score: 100, partial_rerun?: true)
      runner = build_runner(result:)

      allow(Henitai::Runner).to receive(:new) do |**kwargs|
        captured_survivors_from = kwargs[:survivors_from]
        runner
      end

      cli = described_class.new(
        ["run", "--config", config_path, "--survivors-from", report_path]
      )
      cli.define_singleton_method(:exit) { |_status = nil| nil }
      cli.run

      expect(captured_survivors_from).to eq(expected_snapshot_path)
    end
  end

  it "warns and falls back when survivors_from resolution raises" do
    Dir.mktmpdir do |dir|
      config_path = write_configuration(dir)
      report_path = File.join(dir, "mutation-report.json")
      File.write(report_path, JSON.generate("schemaVersion" => "1.0", "files" => {}))
      result = instance_double(Henitai::Result, mutation_score: 100, partial_rerun?: true)
      runner = build_runner(result:)

      allow(JSON).to receive(:parse).and_raise(ArgumentError, "boom")
      allow(Henitai::Runner).to receive(:new).and_return(runner)

      cli = described_class.new(["run", "--config", config_path, "--survivors-from", report_path])
      cli.define_singleton_method(:exit) { |_status = nil| nil }

      expect { cli.run }.to output(
        /could not resolve survivors-from #{Regexp.escape(report_path)}: ArgumentError: boom/
      ).to_stderr
    end
  end

  it "falls back to the original survivors_from path when resolution raises" do
    Dir.mktmpdir do |dir|
      config_path = write_configuration(dir)
      report_path = File.join(dir, "mutation-report.json")
      File.write(report_path, JSON.generate("schemaVersion" => "1.0", "files" => {}))
      captured_survivors_from = :not_set
      result = instance_double(Henitai::Result, mutation_score: 100, partial_rerun?: true)
      runner = build_runner(result:)

      allow(JSON).to receive(:parse).and_raise(ArgumentError, "boom")
      allow(Henitai::Runner).to receive(:new) do |**kwargs|
        captured_survivors_from = kwargs[:survivors_from]
        runner
      end

      cli = described_class.new(["run", "--config", config_path, "--survivors-from", report_path])
      cli.define_singleton_method(:exit) { |_status = nil| nil }
      allow(cli).to receive(:warn)

      cli.run
      expect(captured_survivors_from).to eq(report_path)
    end
  end

  it "exits zero for a partial rerun regardless of score" do
    Dir.mktmpdir do |dir|
      config_path = write_configuration(dir)
      result = instance_double(Henitai::Result, mutation_score: 0, partial_rerun?: true)
      runner = build_runner(result:)

      allow(Henitai::Runner).to receive(:new).and_return(runner)

      cli = described_class.new(["run", "--config", config_path])
      cli.define_singleton_method(:exit) do |status = nil|
        raise "expected exit status 0, got #{status.inspect}" unless status == 0
      end
      expect { cli.run }.to output(/partial rerun - mutation score threshold not evaluated/).to_stderr
    end
  end

  it "exits zero for a partial rerun with survivors when fail-on-survivors is not set" do
    Dir.mktmpdir do |dir|
      config_path = write_configuration(dir)
      result = instance_double(
        Henitai::Result,
        mutation_score: 0,
        partial_rerun?: true,
        survived: 1
      )
      runner = build_runner(result:)

      allow(Henitai::Runner).to receive(:new).and_return(runner)

      cli = described_class.new(["run", "--config", config_path])
      cli.define_singleton_method(:exit) do |status = nil|
        raise "expected exit status 0, got #{status.inspect}" unless status == 0
      end
      expect { cli.run }.to output(/partial rerun - mutation score threshold not evaluated/).to_stderr
    end
  end

  it "exits 1 for a partial rerun when any survivors remain and --fail-on-survivors is set" do
    Dir.mktmpdir do |dir|
      config_path = write_configuration(dir)
      result = instance_double(
        Henitai::Result,
        mutation_score: 0,
        partial_rerun?: true,
        survived: 1
      )
      runner = build_runner(result:)

      allow(Henitai::Runner).to receive(:new).and_return(runner)

      cli = described_class.new(["run", "--config", config_path, "--fail-on-survivors"])
      cli.define_singleton_method(:exit) do |status = nil|
        raise "expected exit status 1, got #{status.inspect}" unless status == 1
      end
      expect { cli.run }.to output(/partial rerun - mutation score threshold not evaluated/).to_stderr
    end
  end

  it "exits 0 for a partial rerun when no survivors remain and --fail-on-survivors is set" do
    Dir.mktmpdir do |dir|
      config_path = write_configuration(dir)
      result = instance_double(
        Henitai::Result,
        mutation_score: 0,
        partial_rerun?: true,
        survived: 0
      )
      runner = build_runner(result:)

      allow(Henitai::Runner).to receive(:new).and_return(runner)

      cli = described_class.new(["run", "--config", config_path, "--fail-on-survivors"])
      cli.define_singleton_method(:exit) do |status = nil|
        raise "expected exit status 0, got #{status.inspect}" unless status == 0
      end
      expect { cli.run }.to output(/partial rerun - mutation score threshold not evaluated/).to_stderr
    end
  end
end
