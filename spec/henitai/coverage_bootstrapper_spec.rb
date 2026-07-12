# frozen_string_literal: true

require "fileutils"
require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::CoverageBootstrapper do
  def build_config
    Struct.new(:reports_dir).new("reports")
  end

  def setup_partial_coverage_workspace(dir)
    source_a = File.join(dir, "lib/a.rb")
    source_b = File.join(dir, "lib/b.rb")
    spec     = File.join(dir, "test/sample_test.rb")

    FileUtils.mkdir_p(File.dirname(source_a))
    FileUtils.mkdir_p(File.dirname(spec))

    File.write(source_a, "class A; end\n")
    File.write(source_b, "class B; end\n")
    File.write(spec, "# test\n")

    [source_a, source_b, spec]
  end

  def write_partial_coverage_report(dir, source_a)
    report = File.join(dir, "reports/coverage/.resultset.json")
    FileUtils.mkdir_p(File.dirname(report))
    File.write(report, {
      "Minitest" => { "coverage" => { File.expand_path(source_a) => { "lines" => [nil, 1] } } }
    }.to_json)
    bump_mtime(report)
  end

  def bump_mtime(path)
    time = Time.now + 10
    File.utime(time, time, path)
  end

  def set_mtime(path, time)
    File.utime(time, time, path)
  end

  def build_bootstrapper(static_filter:, per_test_coverage_available: true)
    described_class.new(static_filter:).tap do |bootstrapper|
      allow(bootstrapper).to receive(:per_test_coverage_available?).and_return(
        per_test_coverage_available
      )
    end
  end

  def with_env(key, value)
    original = ENV.fetch(key, nil)
    ENV[key] = value
    yield
  ensure
    if original.nil?
      ENV.delete(key)
    else
      ENV[key] = original
    end
  end

  def build_integration(test_files:, run_suite_result:)
    instance_double(
      Henitai::Integration::Rspec,
      test_files: test_files,
      run_suite: run_suite_result,
      per_test_coverage_supported?: true
    )
  end

  def build_scoped_bootstrap_workspace(dir)
    paths = bootstrap_workspace_paths(dir)
    write_bootstrap_workspace(paths)
    paths
  end

  def bootstrap_workspace_paths(dir)
    {
      source_a: File.join(dir, "lib/a.rb"),
      source_b: File.join(dir, "lib/b.rb"),
      scoped_spec: File.join(dir, "spec/scoped_spec.rb"),
      full_spec: File.join(dir, "spec/full_spec.rb"),
      report: File.join(dir, "reports/coverage/.resultset.json"),
      per_test_report: File.join(dir, "reports/henitai_per_test.json")
    }
  end

  def write_bootstrap_workspace(paths)
    create_workspace_directories(paths)
    write_workspace_source_files(paths)
    write_workspace_reports(paths)
  end

  def create_workspace_directories(paths)
    FileUtils.mkdir_p(File.dirname(paths[:source_a]))
    FileUtils.mkdir_p(File.dirname(paths[:scoped_spec]))
    FileUtils.mkdir_p(File.dirname(paths[:report]))
  end

  def write_workspace_source_files(paths)
    File.write(paths[:source_a], "class A; end")
    File.write(paths[:source_b], "class B; end")
    File.write(paths[:scoped_spec], "# scoped spec")
    File.write(paths[:full_spec], "# full spec")
  end

  def write_workspace_reports(paths)
    File.write(paths[:report], "{}")
    File.write(paths[:per_test_report], "{}")
    bump_mtime(paths[:report])
    bump_mtime(paths[:per_test_report])
  end

  def build_scoped_bootstrap_integration(scoped_spec, full_spec)
    instance_double(
      Henitai::Integration::Rspec,
      test_files: [scoped_spec, full_spec],
      run_suite: :survived,
      per_test_coverage_supported?: true
    )
  end

  def stub_scoped_bootstrap_coverage(static_filter, source_a, source_b)
    allow(static_filter).to receive(:coverage_lines_for).and_return(
      {},
      { File.expand_path(source_a) => [1] },
      { File.expand_path(source_a) => [1] },
      {
        File.expand_path(source_a) => [1],
        File.expand_path(source_b) => [1]
      }
    )
  end

  it "sets a dedicated coverage dir while bootstrapping the suite" do
    static_filter = instance_double(Henitai::StaticFilter)
    integration = build_integration(
      test_files: ["spec/sample_spec.rb"],
      run_suite_result: :survived
    )

    bootstrapper = build_bootstrapper(static_filter:)

    allow(static_filter).to receive(:coverage_lines_for).and_return(
      { File.expand_path("lib/sample.rb") => [2] }
    )
    allow(integration).to receive(:run_suite) do |_test_files|
      expect(
        [
          ENV.fetch("HENITAI_COVERAGE_DIR", nil),
          ENV.fetch("HENITAI_REPORTS_DIR", nil)
        ]
      ).to eq(
        [
          File.join("reports", "coverage"),
          "reports"
        ]
      )
      :survived
    end

    bootstrapper.ensure!(
      source_files: [File.expand_path("lib/sample.rb")],
      config: build_config,
      integration:
    )
  end

  it "runs the suite when no coverage report exists" do
    static_filter = instance_double(Henitai::StaticFilter)
    integration = build_integration(
      test_files: ["spec/sample_spec.rb"],
      run_suite_result: :survived
    )

    bootstrapper = build_bootstrapper(static_filter:)

    allow(static_filter).to receive(:coverage_lines_for).and_return(
      { File.expand_path("lib/sample.rb") => [2] }
    )
    allow(integration).to receive(:run_suite).and_return(:survived)

    bootstrapper.ensure!(
      source_files: [File.expand_path("lib/sample.rb")],
      config: build_config,
      integration:
    )

    expect(integration).to have_received(:run_suite).with(["spec/sample_spec.rb"])
  end

  it "runs the suite when the per-test coverage report is missing" do
    static_filter = instance_double(Henitai::StaticFilter)
    integration = build_integration(
      test_files: ["spec/sample_spec.rb"],
      run_suite_result: :survived
    )

    bootstrapper = build_bootstrapper(static_filter:)

    allow(static_filter).to receive(:coverage_lines_for).and_return(
      { File.expand_path("lib/sample.rb") => [2] }
    )
    allow(bootstrapper).to receive_messages(
      coverage_fresh?: true,
      coverage_available?: true,
      per_test_coverage_fresh?: false
    )
    allow(integration).to receive(:run_suite).and_return(:survived)

    bootstrapper.ensure!(
      source_files: [File.expand_path("lib/sample.rb")],
      config: build_config,
      integration:
    )

    expect(integration).to have_received(:run_suite).with(["spec/sample_spec.rb"])
  end

  it "accepts a fresh report that only covers part of the configured sources" do
    Dir.mktmpdir do |dir|
      source_a, source_b, spec = setup_partial_coverage_workspace(dir)
      write_partial_coverage_report(dir, source_a)

      config = Struct.new(:reports_dir).new(File.join(dir, "reports"))
      static_filter = instance_double(Henitai::StaticFilter)
      integration = instance_double(
        Henitai::Integration::Minitest,
        test_files: [spec],
        per_test_coverage_supported?: false
      )
      bootstrapper = build_bootstrapper(static_filter:)

      allow(static_filter).to receive(:coverage_lines_for).and_return(
        File.expand_path(source_a) => [1]
      )
      allow(integration).to receive(:run_suite).and_return(:survived)

      bootstrapper.record_dependency_manifest(config)
      bootstrapper.ensure!(source_files: [source_a, source_b], config:, integration:)

      expect(integration).not_to have_received(:run_suite)
    end
  end

  it "restores the coverage dir environment after bootstrapping" do
    static_filter = instance_double(Henitai::StaticFilter)
    integration = build_integration(
      test_files: ["spec/sample_spec.rb"],
      run_suite_result: :survived
    )

    bootstrapper = build_bootstrapper(static_filter:)

    allow(static_filter).to receive(:coverage_lines_for).and_return(
      { File.expand_path("lib/sample.rb") => [2] }
    )

    with_env("HENITAI_COVERAGE_DIR", "preexisting") do
      bootstrapper.ensure!(
        source_files: [File.expand_path("lib/sample.rb")],
        config: build_config,
        integration:
      )

      expect(ENV.fetch("HENITAI_COVERAGE_DIR", nil)).to eq("preexisting")
    end
  end

  it "raises when the coverage bootstrap produces no usable coverage" do
    static_filter = instance_double(Henitai::StaticFilter)
    integration = build_integration(
      test_files: ["spec/sample_spec.rb"],
      run_suite_result: :survived
    )

    bootstrapper = build_bootstrapper(static_filter:)

    allow(static_filter).to receive(:coverage_lines_for).and_return({})
    allow(integration).to receive(:run_suite).and_return(:survived)

    expect do
      bootstrapper.ensure!(
        source_files: [File.expand_path("lib/sample.rb")],
        config: build_config,
        integration:
      )
    end.to raise_error(
      Henitai::CoverageError,
      /coverage/i
    )
  end

  it "includes the failing suite log path and tail in the bootstrap error" do
    static_filter = instance_double(Henitai::StaticFilter)
    failure = Struct.new(:log_path) do
      def tail(_line_count)
        "failure tail"
      end
    end.new("reports/baseline.log")
    integration = build_integration(
      test_files: ["spec/sample_spec.rb"],
      run_suite_result: failure
    )
    bootstrapper = build_bootstrapper(static_filter:)

    allow(static_filter).to receive(:coverage_lines_for).and_return({})

    expect do
      bootstrapper.ensure!(
        source_files: [File.expand_path("lib/sample.rb")],
        config: build_config,
        integration:
      )
    end.to raise_error(
      Henitai::CoverageError,
      %r{reports/baseline\.log.*failure tail}m
    )
  end

  it "uses a generic bootstrap error when the suite has no log path" do
    static_filter = instance_double(Henitai::StaticFilter)
    integration = build_integration(
      test_files: ["spec/sample_spec.rb"],
      run_suite_result: :failed
    )
    bootstrapper = build_bootstrapper(static_filter:)

    allow(static_filter).to receive(:coverage_lines_for).and_return({})

    expect do
      bootstrapper.ensure!(
        source_files: [File.expand_path("lib/sample.rb")],
        config: build_config,
        integration:
      )
    end.to raise_error(
      Henitai::CoverageError,
      "Configured test suite failed while generating coverage"
    )
  end

  it "does not require per-test coverage for integrations that do not support it" do
    Dir.mktmpdir do |dir|
      source = File.join(dir, "lib/sample.rb")
      spec = File.join(dir, "test/sample_test.rb")
      report = File.join(dir, "reports/coverage/.resultset.json")

      FileUtils.mkdir_p(File.dirname(source))
      FileUtils.mkdir_p(File.dirname(spec))
      FileUtils.mkdir_p(File.dirname(report))

      File.write(source, "class Sample; end\n")
      File.write(spec, "# test\n")
      File.write(
        report,
        {
          "RSpec" => {
            "coverage" => {
              File.expand_path(source) => {
                "lines" => [nil, 1]
              }
            }
          }
        }.to_json
      )
      bump_mtime(report)

      config = Struct.new(:reports_dir).new(File.join(dir, "reports"))
      static_filter = instance_double(Henitai::StaticFilter)
      integration = instance_double(
        Henitai::Integration::Minitest,
        test_files: [spec],
        per_test_coverage_supported?: false,
        run_suite: :survived
      )
      bootstrapper = build_bootstrapper(static_filter:)

      allow(static_filter).to receive(:coverage_lines_for).and_return(
        File.expand_path(source) => [2]
      )

      bootstrapper.record_dependency_manifest(config)
      bootstrapper.ensure!(source_files: [source], config:, integration:)

      expect(integration).not_to have_received(:run_suite)
    end
  end

  # ---------------------------------------------------------------------------
  # Option 1: coverage freshness check
  # ---------------------------------------------------------------------------

  describe "freshness check" do
    it "skips the bootstrap when the coverage report is newer than all watched files and covers the sources" do
      Dir.mktmpdir do |dir|
        source = File.join(dir, "lib/sample.rb")
        spec   = File.join(dir, "spec/sample_spec.rb")
        report = File.join(dir, "reports/coverage/.resultset.json")

        FileUtils.mkdir_p(File.dirname(source))
        FileUtils.mkdir_p(File.dirname(spec))
        FileUtils.mkdir_p(File.dirname(report))

        File.write(source, "class Sample; end")
        File.write(spec,   "# spec")
        File.write(report, "{}")
        bump_mtime(report)

        config = Struct.new(:reports_dir).new(File.join(dir, "reports"))
        static_filter = instance_double(Henitai::StaticFilter)
        integration = instance_spy(
          Henitai::Integration::Rspec,
          test_files: [spec]
        )
        bootstrapper = build_bootstrapper(static_filter:)

        allow(static_filter).to receive(:coverage_lines_for).and_return(
          { File.expand_path(source) => [1] }
        )
        allow(bootstrapper).to receive(:per_test_coverage_fresh?).and_return(true)

        bootstrapper.record_dependency_manifest(config)
        bootstrapper.ensure!(source_files: [source], config:, integration:)

        expect(integration).not_to have_received(:run_suite)
      end
    end

    it "still bootstraps when a dependency file is newer than the coverage report" do
      Dir.mktmpdir do |dir|
        source  = File.join(dir, "lib/sample.rb")
        spec    = File.join(dir, "spec/sample_spec.rb")
        support = File.join(dir, "spec/support/helpers.rb")
        report  = File.join(dir, "reports/coverage/.resultset.json")

        [source, spec, support, report].each { |path| FileUtils.mkdir_p(File.dirname(path)) }

        File.write(source, "class Sample; end")
        File.write(spec,   "# spec")
        File.write(report, "{}")
        bump_mtime(report)
        File.write(support, "# support edited after the report")
        bump_mtime(support)

        config = Struct.new(:reports_dir).new(File.join(dir, "reports"))
        static_filter = instance_double(Henitai::StaticFilter)
        integration = instance_double(
          Henitai::Integration::Rspec,
          test_files: [spec],
          run_suite: :survived
        )
        bootstrapper = build_bootstrapper(static_filter:)

        allow(static_filter).to receive(:coverage_lines_for).and_return(
          { File.expand_path(source) => [1] }
        )
        allow(bootstrapper).to receive(:per_test_coverage_fresh?).and_return(true)

        Dir.chdir(dir) do
          # Manifest matches — only the support file's mtime makes it stale.
          bootstrapper.record_dependency_manifest(config)
          bootstrapper.ensure!(source_files: [source], config:, integration:)
        end

        expect(integration).to have_received(:run_suite)
      end
    end

    it "still bootstraps when a dependency file was deleted after the coverage report" do
      Dir.mktmpdir do |dir|
        source  = File.join(dir, "lib/sample.rb")
        spec    = File.join(dir, "spec/sample_spec.rb")
        support = File.join(dir, "spec/support/helpers.rb")
        report  = File.join(dir, "reports/coverage/.resultset.json")

        [source, spec, support, report].each { |path| FileUtils.mkdir_p(File.dirname(path)) }

        File.write(source, "class Sample; end")
        File.write(spec,   "# spec")
        File.write(support, "# support")
        File.write(report, "{}")

        config = Struct.new(:reports_dir).new(File.join(dir, "reports"))
        static_filter = instance_double(Henitai::StaticFilter)
        integration = instance_double(
          Henitai::Integration::Rspec,
          test_files: [spec],
          run_suite: :survived
        )
        bootstrapper = build_bootstrapper(static_filter:)

        allow(static_filter).to receive(:coverage_lines_for).and_return(
          { File.expand_path(source) => [1] }
        )
        allow(bootstrapper).to receive(:per_test_coverage_fresh?).and_return(true)

        Dir.chdir(dir) do
          # Manifest recorded while the support file existed, report fresh.
          bootstrapper.record_dependency_manifest(config)
          bump_mtime(report)

          # Deleting the dependency must invalidate the coverage artifacts
          # even though every *remaining* watched file is older than the
          # report — the path set changed, not a surviving file's mtime.
          FileUtils.rm(support)

          bootstrapper.ensure!(source_files: [source], config:, integration:)
        end

        expect(integration).to have_received(:run_suite)
      end
    end

    it "skips the bootstrap when per-test coverage is also fresh" do
      Dir.mktmpdir do |dir|
        source = File.join(dir, "lib/sample.rb")
        spec = File.join(dir, "spec/sample_spec.rb")
        report = File.join(dir, "reports/coverage/.resultset.json")
        per_test_report = File.join(dir, "reports/henitai_per_test.json")
        now = Time.now

        FileUtils.mkdir_p(File.dirname(source))
        FileUtils.mkdir_p(File.dirname(spec))
        FileUtils.mkdir_p(File.dirname(report))
        File.write(source, "class Sample; end")
        File.write(spec, "# spec")
        File.write(report, "{}")
        File.write(per_test_report, "{}")
        set_mtime(source, now - 30)
        set_mtime(spec, now - 30)
        set_mtime(report, now - 10)
        set_mtime(per_test_report, now - 10)

        config = Struct.new(:reports_dir).new(File.join(dir, "reports"))
        static_filter = instance_double(Henitai::StaticFilter)
        integration = instance_double(
          Henitai::Integration::Rspec,
          test_files: [spec],
          per_test_coverage_supported?: true
        )
        bootstrapper = described_class.new(static_filter:)

        allow(static_filter).to receive(:coverage_lines_for).and_return(
          File.expand_path(source) => [1]
        )
        allow(integration).to receive(:run_suite).and_return(:survived)

        bootstrapper.record_dependency_manifest(config)
        bootstrapper.ensure!(source_files: [source], config:, integration:)

        expect(integration).not_to have_received(:run_suite)
      end
    end

    it "still bootstraps when the fresh report does not cover the configured sources" do
      Dir.mktmpdir do |dir|
        source = File.join(dir, "lib/sample.rb")
        spec   = File.join(dir, "spec/sample_spec.rb")
        report = File.join(dir, "reports/coverage/.resultset.json")

        FileUtils.mkdir_p(File.dirname(source))
        FileUtils.mkdir_p(File.dirname(spec))
        FileUtils.mkdir_p(File.dirname(report))

        File.write(source, "class Sample; end")
        File.write(spec,   "# spec")
        File.write(report, "{}") # fresh but empty — no coverage for source
        bump_mtime(report)

        config = Struct.new(:reports_dir).new(File.join(dir, "reports"))
        static_filter = instance_double(Henitai::StaticFilter)
        integration = instance_double(
          Henitai::Integration::Rspec,
          test_files: [spec],
          run_suite: :survived
        )
        bootstrapper = build_bootstrapper(static_filter:)

        # First call (freshness guard): no coverage → bootstrap runs
        # Second call (post-bootstrap guard): coverage is now available
        allow(static_filter).to receive(:coverage_lines_for).and_return(
          {},
          { File.expand_path(source) => [1] }
        )
        allow(bootstrapper).to receive(:per_test_coverage_fresh?).and_return(true)
        allow(integration).to receive(:run_suite).and_return(:survived)

        bootstrapper.record_dependency_manifest(config)
        bootstrapper.ensure!(source_files: [source], config:, integration:)

        expect(integration).to have_received(:run_suite)
      end
    end

    it "runs the bootstrap when a source file is newer than the coverage report" do
      Dir.mktmpdir do |dir|
        source = File.join(dir, "lib/sample.rb")
        spec   = File.join(dir, "spec/sample_spec.rb")
        report = File.join(dir, "reports/coverage/.resultset.json")

        FileUtils.mkdir_p(File.dirname(source))
        FileUtils.mkdir_p(File.dirname(spec))
        FileUtils.mkdir_p(File.dirname(report))

        File.write(spec, "# spec")

        # Write report before source so source is newer
        File.write(report, "{}")
        File.write(source, "class Sample; end")
        set_mtime(report, Time.now - 10)
        bump_mtime(source)

        config = Struct.new(:reports_dir).new(File.join(dir, "reports"))
        static_filter = instance_double(Henitai::StaticFilter)
        integration = instance_double(
          Henitai::Integration::Rspec,
          test_files: [spec],
          run_suite: :survived
        )
        bootstrapper = build_bootstrapper(static_filter:)

        allow(static_filter).to receive(:coverage_lines_for).and_return(
          { File.expand_path(source) => [1] }
        )
        allow(integration).to receive(:run_suite).and_return(:survived)

        bootstrapper.ensure!(source_files: [source], config:, integration:)

        expect(integration).to have_received(:run_suite)
      end
    end

    it "runs the bootstrap when a test file is newer than the coverage report" do
      Dir.mktmpdir do |dir|
        source = File.join(dir, "lib/sample.rb")
        spec   = File.join(dir, "spec/sample_spec.rb")
        report = File.join(dir, "reports/coverage/.resultset.json")

        FileUtils.mkdir_p(File.dirname(source))
        FileUtils.mkdir_p(File.dirname(spec))
        FileUtils.mkdir_p(File.dirname(report))

        File.write(source, "class Sample; end")

        # Write report before spec so spec is newer
        File.write(report, "{}")
        File.write(spec, "# updated spec")
        set_mtime(report, Time.now - 10)
        bump_mtime(spec)

        config = Struct.new(:reports_dir).new(File.join(dir, "reports"))
        static_filter = instance_double(Henitai::StaticFilter)
        integration = instance_double(
          Henitai::Integration::Rspec,
          test_files: [spec],
          run_suite: :survived
        )
        bootstrapper = build_bootstrapper(static_filter:)

        allow(static_filter).to receive(:coverage_lines_for).and_return(
          { File.expand_path(source) => [1] }
        )
        allow(integration).to receive(:run_suite).and_return(:survived)

        bootstrapper.ensure!(source_files: [source], config:, integration:)

        expect(integration).to have_received(:run_suite)
      end
    end

    it "watches explicitly scoped test files for freshness" do
      Dir.mktmpdir do |dir|
        source = File.join(dir, "lib/sample.rb")
        scoped_spec = File.join(dir, "spec/scoped_spec.rb")
        report = File.join(dir, "reports/coverage/.resultset.json")
        now = Time.now

        FileUtils.mkdir_p(File.dirname(source))
        FileUtils.mkdir_p(File.dirname(scoped_spec))
        FileUtils.mkdir_p(File.dirname(report))
        File.write(source, "class Sample; end")
        File.write(scoped_spec, "# scoped spec")
        File.write(report, "{}")
        set_mtime(source, now - 30)
        set_mtime(report, now - 20)
        set_mtime(scoped_spec, now - 10)

        config = Struct.new(:reports_dir).new(File.join(dir, "reports"))
        static_filter = instance_double(Henitai::StaticFilter)
        integration = instance_double(
          Henitai::Integration::Minitest,
          test_files: [scoped_spec],
          per_test_coverage_supported?: false,
          run_suite: :survived
        )
        bootstrapper = build_bootstrapper(static_filter:)

        allow(static_filter).to receive(:coverage_lines_for).and_return(
          File.expand_path(source) => [1]
        )

        bootstrapper.ensure!(
          source_files: [source],
          config:,
          integration:,
          test_files: [scoped_spec]
        )

        expect(integration).to have_received(:run_suite).with([scoped_spec])
      end
    end

    it "treats a file that no longer exists as stale" do
      Dir.mktmpdir do |dir|
        source  = File.join(dir, "lib/sample.rb")
        ghost   = File.join(dir, "lib/deleted.rb")
        spec    = File.join(dir, "spec/sample_spec.rb")
        report  = File.join(dir, "reports/coverage/.resultset.json")

        FileUtils.mkdir_p(File.dirname(source))
        FileUtils.mkdir_p(File.dirname(spec))
        FileUtils.mkdir_p(File.dirname(report))

        File.write(source, "class Sample; end")
        File.write(spec,   "# spec")
        File.write(report, "{}")
        bump_mtime(report)
        # ghost is never created — simulates a deleted file in the watch list

        config = Struct.new(:reports_dir).new(File.join(dir, "reports"))
        static_filter = instance_double(Henitai::StaticFilter)
        integration = instance_double(
          Henitai::Integration::Rspec,
          test_files: [spec],
          run_suite: :survived
        )
        bootstrapper = build_bootstrapper(static_filter:)

        allow(static_filter).to receive(:coverage_lines_for).and_return(
          { File.expand_path(source) => [1] }
        )
        allow(integration).to receive(:run_suite).and_return(:survived)

        bootstrapper.ensure!(source_files: [source, ghost], config:, integration:)

        expect(integration).to have_received(:run_suite)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Option 3: scoped test files forwarding
  # ---------------------------------------------------------------------------

  describe "scoped test files" do
    it "passes explicit test_files to run_suite instead of all tests" do
      static_filter = instance_double(Henitai::StaticFilter)
      integration = instance_double(
        Henitai::Integration::Rspec,
        test_files: ["spec/other_spec.rb"]
      )
      bootstrapper = build_bootstrapper(static_filter:)

      allow(static_filter).to receive(:coverage_lines_for).and_return(
        { File.expand_path("lib/sample.rb") => [1] }
      )
      allow(integration).to receive(:run_suite).and_return(:survived)

      bootstrapper.ensure!(
        source_files: [File.expand_path("lib/sample.rb")],
        config: build_config,
        integration:,
        test_files: ["spec/sample_spec.rb"]
      )

      expect(integration).to have_received(:run_suite).with(["spec/sample_spec.rb"])
    end

    it "discovers integration.test_files once when test_files are omitted" do
      Dir.mktmpdir do |dir|
        source = File.join(dir, "lib/sample.rb")
        spec = File.join(dir, "spec/sample_spec.rb")

        FileUtils.mkdir_p(File.dirname(source))
        FileUtils.mkdir_p(File.dirname(spec))

        File.write(source, "class Sample; end\n")
        File.write(spec, "# spec\n")

        config = Struct.new(:reports_dir).new(File.join(dir, "reports"))
        static_filter = instance_double(Henitai::StaticFilter)
        integration = instance_double(
          Henitai::Integration::Rspec,
          per_test_coverage_supported?: false
        )
        bootstrapper = build_bootstrapper(static_filter:)

        allow(static_filter).to receive(:coverage_lines_for).and_return(
          { File.expand_path(source) => [1] }
        )
        allow(integration).to receive_messages(
          test_files: [spec],
          run_suite: :survived
        )

        bootstrapper.ensure!(
          source_files: [source],
          config:,
          integration:
        )

        expect(integration).to have_received(:test_files).once
      end
    end

    it "uses integration.test_files when test_files is nil" do
      static_filter = instance_double(Henitai::StaticFilter)
      integration = build_integration(
        test_files: ["spec/sample_spec.rb"],
        run_suite_result: :survived
      )
      bootstrapper = build_bootstrapper(static_filter:)

      allow(static_filter).to receive(:coverage_lines_for).and_return(
        { File.expand_path("lib/sample.rb") => [1] }
      )
      allow(integration).to receive(:run_suite).and_return(:survived)

      bootstrapper.ensure!(
        source_files: [File.expand_path("lib/sample.rb")],
        config: build_config,
        integration:,
        test_files: nil
      )

      expect(integration).to have_received(:run_suite).with(["spec/sample_spec.rb"])
    end

    it "uses the coverage directory when config has no reports_dir", :aggregate_failures do
      static_filter = instance_double(Henitai::StaticFilter)
      integration = build_integration(
        test_files: ["spec/sample_spec.rb"],
        run_suite_result: :survived
      )
      bootstrapper = build_bootstrapper(static_filter:)
      config = Struct.new(:timeout).new(10.0)

      allow(static_filter).to receive(:coverage_lines_for).and_return(
        { File.expand_path("lib/sample.rb") => [1] }
      )

      expect do
        bootstrapper.ensure!(
          source_files: [File.expand_path("lib/sample.rb")],
          config:,
          integration:
        )
      end.not_to raise_error
      expect(integration).to have_received(:run_suite).with(["spec/sample_spec.rb"])
    end

    it "uses scoped test_files for the freshness watch list" do
      Dir.mktmpdir do |dir|
        source       = File.join(dir, "lib/sample.rb")
        scoped_spec  = File.join(dir, "spec/sample_spec.rb")
        unrelated    = File.join(dir, "spec/other_spec.rb")
        report       = File.join(dir, "reports/coverage/.resultset.json")

        FileUtils.mkdir_p(File.dirname(source))
        FileUtils.mkdir_p(File.dirname(scoped_spec))
        FileUtils.mkdir_p(File.dirname(report))

        File.write(source,      "class Sample; end")
        File.write(scoped_spec, "# scoped spec")
        File.write(report, "{}")
        # unrelated spec is newer — written after the report
        File.write(unrelated, "# unrelated newer spec")
        bump_mtime(report)
        bump_mtime(unrelated)

        config = Struct.new(:reports_dir).new(File.join(dir, "reports"))
        static_filter = instance_double(Henitai::StaticFilter)
        integration = instance_double(
          Henitai::Integration::Rspec,
          test_files: [scoped_spec, unrelated]
        )
        bootstrapper = build_bootstrapper(static_filter:)

        allow(static_filter).to receive(:coverage_lines_for).and_return(
          { File.expand_path(source) => [1] }
        )
        allow(bootstrapper).to receive(:per_test_coverage_fresh?).and_return(true)

        # Only the scoped spec is watched — the newer unrelated spec is ignored
        allow(integration).to receive(:run_suite)

        bootstrapper.record_dependency_manifest(config)
        bootstrapper.ensure!(
          source_files: [source],
          config:,
          integration:,
          test_files: [scoped_spec]
        )

        expect(integration).not_to have_received(:run_suite)
      end
    end
  end
end
