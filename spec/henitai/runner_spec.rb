# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength

require "fileutils"
require "json"
require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::Runner do
  before do
    stub_const(
      "RunnerSpecConfig",
      Struct.new(
        :includes,
        :operators,
        :timeout,
        :reporters,
        :thresholds,
        :integration,
        :reports_dir
      )
    )

    coverage_bootstrapper = instance_double(Henitai::CoverageBootstrapper)
    allow(coverage_bootstrapper).to receive(:ensure!)
    allow(Henitai::CoverageBootstrapper).to receive(:new).and_return(
      coverage_bootstrapper
    )
  end

  def build_config(overrides = {})
    values = default_config_values.merge(overrides)

    RunnerSpecConfig.new(
      values[:includes],
      values[:operators],
      values[:timeout],
      values[:reporters],
      values[:thresholds],
      values[:integration],
      values[:reports_dir]
    )
  end

  def default_config_values
    {
      includes: ["lib"],
      operators: :light,
      timeout: 10.0,
      reporters: ["terminal"],
      thresholds: { low: 60, high: 80 },
      integration: "rspec",
      reports_dir: "reports"
    }
  end

  def build_subject(expression, source_file: nil)
    source_location = source_file && { file: source_file, range: 1..3 }

    Henitai::Subject.new(
      expression:,
      source_location:
    )
  end

  def build_mutant(subject)
    Struct.new(:subject, :status).new(subject, :pending)
  end

  def build_result(mutants)
    Struct.new(:mutants).new(mutants)
  end

  def build_loaded_survivors(survivor_ids, coverage_map: {}, git_sha: "deadbeef")
    Struct.new(:survivor_ids, :coverage_map, :git_sha).new(
      survivor_ids,
      coverage_map,
      git_sha
    )
  end

  def build_mutant_status(status = :pending)
    Struct.new(:status).new(status)
  end

  def build_history_store(calls = nil)
    history_store = instance_double(Henitai::MutantHistoryStore)
    allow(history_store).to receive(:record) do |_result, **_kwargs|
      calls << :history if calls
    end
    history_store
  end

  # The bootstrap runs in a background thread (option 2) so bootstrap and
  # generate are concurrent. We check:
  #   - every phase fires with the correct arguments
  #   - the partial ordering guaranteed by the implementation holds:
  #       resolve < generate  (both sequential in main thread)
  #       bootstrap < filter  (thread is joined before filter)
  #       generate  < filter  (sequential in main thread)
  #       filter    < execute (sequential in main thread)
  it "runs the pipeline and reports the result" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib"))
      File.write(File.join(dir, "lib/sample.rb"), "class Sample; end\n")

      Dir.chdir(dir) do
        config = build_config
        runner = described_class.new(config:)
        subject = build_subject("Sample#answer", source_file: "lib/sample.rb")
        subjects = [subject]
        mutants = [build_mutant(subject)]
        result = build_result(mutants)
        mu = Mutex.new
        calls = []
        subject_resolver = instance_double(Henitai::SubjectResolver)
        mutant_generator = instance_double(Henitai::MutantGenerator)
        static_filter = instance_double(Henitai::StaticFilter)
        coverage_bootstrapper = instance_double(Henitai::CoverageBootstrapper)
        execution_engine = instance_double(Henitai::ExecutionEngine)
        integration = instance_double(Henitai::Integration::Rspec)
        history_store = build_history_store(calls)
        reporter = instance_double(Henitai::Reporter::Terminal)

        allow(Henitai::Reporter::Terminal).to receive(:new).and_return(reporter)
        allow(runner).to receive_messages(
          coverage_bootstrapper:,
          subject_resolver:,
          mutant_generator:,
          static_filter:,
          execution_engine:,
          integration:,
          history_store:
        )
        allow(subject_resolver).to receive(:resolve_from_files) do |paths|
          mu.synchronize { calls << [:resolve_from_files, paths] }
          subjects
        end
        allow(coverage_bootstrapper).to receive(:ensure!) do |kwargs|
          mu.synchronize { calls << [:bootstrap, kwargs[:source_files], kwargs[:config]] }
        end
        allow(mutant_generator).to receive(:generate) do |resolved_subjects, operators, kwargs|
          mu.synchronize do
            calls << [:generate, resolved_subjects, operators.map(&:class), kwargs[:config]]
          end
          mutants
        end
        allow(static_filter).to receive(:apply) do |current_mutants, received_config|
          mu.synchronize { calls << [:filter, current_mutants, received_config] }
          mutants
        end
        allow(execution_engine).to receive(:run) do |current_mutants,
                                                     current_integration,
                                                     received_config,
                                                     progress_reporter:|
          mu.synchronize do
            calls << [:execute, current_mutants, current_integration, received_config,
                      progress_reporter]
          end
          mutants
        end
        allow(Henitai::Result).to receive(:new) do |kwargs|
          mu.synchronize do
            calls << [:result, kwargs[:mutants], kwargs[:started_at].is_a?(Time),
                      kwargs[:finished_at].is_a?(Time), kwargs[:thresholds]]
          end
          result
        end
        allow(Henitai::Reporter).to receive(:run_all) do |kwargs|
          mu.synchronize { calls << [:report, kwargs] }
        end

        runner.run

        expect(calls).to satisfy do |events|
          resolve_call = [:resolve_from_files, ["lib/sample.rb"]]
          bootstrap_call = [:bootstrap, ["lib/sample.rb"], config]
          generate_call = [:generate, subjects, Henitai::Operator.for_set(:light).map(&:class), config]
          filter_call = [:filter, mutants, config]
          execute_call = [:execute, mutants, integration, config, reporter]
          result_call = [:result, mutants, true, true, config.thresholds]
          report_call = [:report, { names: ["terminal"], result:, config: }]

          resolve_index = events.index(resolve_call)
          bootstrap_index = events.index(bootstrap_call)
          generate_index = events.index(generate_call)
          filter_index = events.index(filter_call)
          execute_index = events.index(execute_call)
          result_index = events.index(result_call)
          report_index = events.index(report_call)

          resolve_index && bootstrap_index && generate_index &&
            filter_index && execute_index && result_index && report_index &&
            resolve_index < generate_index &&
            bootstrap_index < filter_index &&
            generate_index < filter_index &&
            filter_index < execute_index &&
            result_index < report_index &&
            events.include?(:history)
        end
      end
    end
  end

  # Option 2: bootstrap and generate_mutants proceed concurrently.
  it "generates mutants while the coverage bootstrap is in progress" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib"))
      File.write(File.join(dir, "lib/sample.rb"), "class Sample; end\n")

      Dir.chdir(dir) do
        config = build_config(reporters: [])
        runner = described_class.new(config:)
        subject_resolver = instance_double(Henitai::SubjectResolver)
        mutant_generator = instance_double(Henitai::MutantGenerator)
        static_filter = instance_double(Henitai::StaticFilter)
        coverage_bootstrapper = instance_double(Henitai::CoverageBootstrapper)
        execution_engine = instance_double(Henitai::ExecutionEngine)
        integration = instance_double(Henitai::Integration::Rspec)
        history_store = build_history_store
        result = build_result([])
        events = []
        mu = Mutex.new

        allow(runner).to receive_messages(
          coverage_bootstrapper:,
          subject_resolver:,
          mutant_generator:,
          static_filter:,
          execution_engine:,
          integration:,
          history_store:
        )
        allow(subject_resolver).to receive(:resolve_from_files).and_return([])
        allow(coverage_bootstrapper).to receive(:ensure!) do |**|
          sleep 0.04 # hold the bootstrap thread open long enough for generate to run
          mu.synchronize { events << :bootstrap_end }
        end
        allow(mutant_generator).to receive(:generate) do |*|
          mu.synchronize { events << :generate }
          []
        end
        allow(static_filter).to receive(:apply).and_return([])
        allow(execution_engine).to receive(:run).and_return([])
        allow(Henitai::Result).to receive(:new).and_return(result)
        allow(Henitai::Reporter).to receive(:run_all)

        runner.run

        # generate must complete before the bootstrap finishes sleeping
        expect(events.index(:generate)).to be < events.index(:bootstrap_end)
      end
    end
  end

  # Targeted runs still bootstrap the full suite.
  it "passes nil test_files to the bootstrapper for targeted runs" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib"))
      File.write(File.join(dir, "lib/sample.rb"), "class Sample; end\n")

      Dir.chdir(dir) do
        config = build_config(reporters: [])
        runner = described_class.new(
          config:,
          subjects: [Henitai::Subject.parse("Sample*")]
        )
        subject = build_subject("Sample#answer", source_file: "lib/sample.rb")
        subject_resolver = instance_double(Henitai::SubjectResolver)
        mutant_generator = instance_double(Henitai::MutantGenerator)
        static_filter = instance_double(Henitai::StaticFilter)
        coverage_bootstrapper = instance_double(Henitai::CoverageBootstrapper)
        execution_engine = instance_double(Henitai::ExecutionEngine)
        integration = instance_double(Henitai::Integration::Rspec)
        history_store = build_history_store
        result = build_result([])
        received_test_files = nil

        allow(runner).to receive_messages(
          coverage_bootstrapper:,
          subject_resolver:,
          mutant_generator:,
          static_filter:,
          execution_engine:,
          integration:,
          history_store:
        )
        allow(subject_resolver).to receive_messages(resolve_from_files: [subject], apply_pattern: [subject])
        allow(integration).to receive(:select_tests).with(subject).and_return(
          ["spec/sample_spec.rb"]
        )
        allow(coverage_bootstrapper).to receive(:ensure!) do |**kwargs|
          received_test_files = kwargs[:test_files]
        end
        allow(mutant_generator).to receive(:generate).and_return([])
        allow(static_filter).to receive(:apply).and_return([])
        allow(execution_engine).to receive(:run).and_return([])
        allow(Henitai::Result).to receive(:new).and_return(result)
        allow(Henitai::Reporter).to receive(:run_all)

        runner.run

        expect(received_test_files).to be_nil
      end
    end
  end

  # Option 3: full runs (no subject pattern) pass nil so all tests are used.
  it "passes nil test_files to the bootstrapper for full runs" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib"))
      File.write(File.join(dir, "lib/sample.rb"), "class Sample; end\n")

      Dir.chdir(dir) do
        config = build_config(reporters: [])
        runner = described_class.new(config:)
        subject_resolver = instance_double(Henitai::SubjectResolver)
        mutant_generator = instance_double(Henitai::MutantGenerator)
        static_filter = instance_double(Henitai::StaticFilter)
        coverage_bootstrapper = instance_double(Henitai::CoverageBootstrapper)
        execution_engine = instance_double(Henitai::ExecutionEngine)
        integration = instance_double(Henitai::Integration::Rspec)
        history_store = build_history_store
        result = build_result([])
        received_test_files = :not_set

        allow(runner).to receive_messages(
          coverage_bootstrapper:,
          subject_resolver:,
          mutant_generator:,
          static_filter:,
          execution_engine:,
          integration:,
          history_store:
        )
        allow(subject_resolver).to receive(:resolve_from_files).and_return([])
        allow(coverage_bootstrapper).to receive(:ensure!) do |**kwargs|
          received_test_files = kwargs[:test_files]
        end
        allow(mutant_generator).to receive(:generate).and_return([])
        allow(static_filter).to receive(:apply).and_return([])
        allow(execution_engine).to receive(:run).and_return([])
        allow(Henitai::Result).to receive(:new).and_return(result)
        allow(Henitai::Reporter).to receive(:run_all)

        runner.run

        expect(received_test_files).to be_nil
      end
    end
  end

  it "uses included Ruby files when no --since ref is given" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib"))
      FileUtils.mkdir_p(File.join(dir, "app"))
      File.write(File.join(dir, "lib/sample.rb"), "class Sample; end\n")
      File.write(File.join(dir, "app/tool.rb"), "class Tool; end\n")

      Dir.chdir(dir) do
        config = build_config(includes: %w[lib app], reporters: [])
        runner = described_class.new(config:)
        subject_resolver = instance_double(Henitai::SubjectResolver)
        mutant_generator = instance_double(Henitai::MutantGenerator)
        static_filter = instance_double(Henitai::StaticFilter)
        execution_engine = instance_double(Henitai::ExecutionEngine)
        integration = instance_double(Henitai::Integration::Rspec)
        history_store = build_history_store
        result = build_result([])
        calls = []

        allow(runner).to receive_messages(
          subject_resolver:,
          mutant_generator:,
          static_filter:,
          execution_engine:,
          integration:,
          history_store:
        )
        allow(subject_resolver).to receive(:resolve_from_files) do |paths|
          calls << paths
          []
        end
        allow(mutant_generator).to receive(:generate).and_return([])
        allow(static_filter).to receive(:apply).and_return([])
        allow(execution_engine).to receive(:run).and_return([])
        allow(Henitai::Result).to receive(:new).and_return(result)
        allow(Henitai::Reporter).to receive(:run_all)

        runner.run

        expect(calls).to eq([%w[lib/sample.rb app/tool.rb]])
      end
    end
  end

  it "includes nested Ruby files from include paths" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib", "nested"))
      File.write(File.join(dir, "lib", "nested", "sample.rb"), "class Sample; end\n")

      Dir.chdir(dir) do
        config = build_config(reporters: [])
        runner = described_class.new(config:)
        subject_resolver = instance_double(Henitai::SubjectResolver)
        mutant_generator = instance_double(Henitai::MutantGenerator)
        static_filter = instance_double(Henitai::StaticFilter)
        execution_engine = instance_double(Henitai::ExecutionEngine)
        integration = instance_double(Henitai::Integration::Rspec)
        history_store = build_history_store
        result = build_result([])
        calls = []

        allow(runner).to receive_messages(
          subject_resolver:,
          mutant_generator:,
          static_filter:,
          execution_engine:,
          integration:,
          history_store:
        )
        allow(subject_resolver).to receive(:resolve_from_files) do |paths|
          calls << paths
          []
        end
        allow(mutant_generator).to receive(:generate).and_return([])
        allow(static_filter).to receive(:apply).and_return([])
        allow(execution_engine).to receive(:run).and_return([])
        allow(Henitai::Result).to receive(:new).and_return(result)
        allow(Henitai::Reporter).to receive(:run_all)

        runner.run

        expect(calls).to eq([[
                              File.join("lib", "nested", "sample.rb")
                            ]])
      end
    end
  end

  it "passes nil progress reporter when terminal output is disabled" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib"))
      File.write(File.join(dir, "lib/sample.rb"), "class Sample; end\n")

      Dir.chdir(dir) do
        config = build_config(reporters: [])
        runner = described_class.new(config:)
        subject_resolver = instance_double(Henitai::SubjectResolver)
        mutant_generator = instance_double(Henitai::MutantGenerator)
        static_filter = instance_double(Henitai::StaticFilter)
        execution_engine = instance_double(Henitai::ExecutionEngine)
        integration = instance_double(Henitai::Integration::Rspec)
        history_store = build_history_store
        result = build_result([])

        allow(runner).to receive_messages(
          subject_resolver:,
          mutant_generator:,
          static_filter:,
          execution_engine:,
          integration:,
          history_store:
        )
        allow(subject_resolver).to receive(:resolve_from_files).and_return([])
        allow(mutant_generator).to receive(:generate).and_return([])
        allow(static_filter).to receive(:apply).and_return([])
        allow(execution_engine).to receive(:run) do |_mutants, _integration, _config, progress_reporter:|
          expect(progress_reporter).to be_nil
          []
        end
        allow(Henitai::Result).to receive(:new).and_return(result)
        allow(Henitai::Reporter).to receive(:run_all)

        runner.run
      end
    end
  end

  it "builds a terminal progress reporter when terminal output is enabled" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib"))
      File.write(File.join(dir, "lib/sample.rb"), "class Sample; end\n")

      Dir.chdir(dir) do
        config = build_config(reporters: ["terminal"])
        runner = described_class.new(config:)
        subject_resolver = instance_double(Henitai::SubjectResolver)
        mutant_generator = instance_double(Henitai::MutantGenerator)
        static_filter = instance_double(Henitai::StaticFilter)
        execution_engine = instance_double(Henitai::ExecutionEngine)
        integration = instance_double(Henitai::Integration::Rspec)
        history_store = build_history_store
        result = build_result([])

        allow(runner).to receive_messages(
          subject_resolver:,
          mutant_generator:,
          static_filter:,
          execution_engine:,
          integration:,
          history_store:
        )
        allow(subject_resolver).to receive(:resolve_from_files).and_return([])
        allow(mutant_generator).to receive(:generate).and_return([])
        allow(static_filter).to receive(:apply).and_return([])
        allow(execution_engine).to receive(:run) do |_mutants, _integration, _config, progress_reporter:|
          expect(progress_reporter).to be_a(Henitai::Reporter::Terminal)
          []
        end
        allow(Henitai::Result).to receive(:new).and_return(result)
        allow(Henitai::Reporter).to receive(:run_all)

        runner.run
      end
    end
  end

  it "passes the configured reports dir to the execution engine" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib"))
      File.write(File.join(dir, "lib/sample.rb"), "class Sample; end\n")

      Dir.chdir(dir) do
        config = build_config(reporters: [], reports_dir: "custom-reports")
        runner = described_class.new(config:)
        subject_resolver = instance_double(Henitai::SubjectResolver)
        mutant_generator = instance_double(Henitai::MutantGenerator)
        static_filter = instance_double(Henitai::StaticFilter)
        execution_engine = instance_double(Henitai::ExecutionEngine)
        integration = instance_double(Henitai::Integration::Rspec)
        history_store = build_history_store
        result = build_result([])

        allow(runner).to receive_messages(
          subject_resolver:,
          mutant_generator:,
          static_filter:,
          execution_engine:,
          integration:,
          history_store:
        )
        allow(subject_resolver).to receive(:resolve_from_files).and_return([])
        allow(mutant_generator).to receive(:generate).and_return([])
        allow(static_filter).to receive(:apply).and_return([])
        allow(execution_engine).to receive(:run) do |_mutants, _integration, received_config, **_kwargs|
          expect(received_config.reports_dir).to eq("custom-reports")
          []
        end
        allow(Henitai::Result).to receive(:new).and_return(result)
        allow(Henitai::Reporter).to receive(:run_all)

        runner.run
      end
    end
  end

  it "restricts Gate 1 to changed files when --since is given" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib"))
      File.write(File.join(dir, "lib/sample.rb"), "class Sample; end\n")

      Dir.chdir(dir) do
        config = build_config(reporters: [])
        runner = described_class.new(config:, since: "HEAD~1")
        subject_resolver = instance_double(Henitai::SubjectResolver)
        diff_analyzer = instance_double(Henitai::GitDiffAnalyzer)
        mutant_generator = instance_double(Henitai::MutantGenerator)
        static_filter = instance_double(Henitai::StaticFilter)
        execution_engine = instance_double(Henitai::ExecutionEngine)
        integration = instance_double(Henitai::Integration::Rspec)
        history_store = build_history_store
        result = build_result([])
        calls = []

        allow(runner).to receive_messages(
          subject_resolver:,
          git_diff_analyzer: diff_analyzer,
          mutant_generator:,
          static_filter:,
          execution_engine:,
          integration:,
          history_store:
        )
        allow(diff_analyzer).to receive(:changed_files) do |kwargs|
          calls << kwargs
          ["lib/sample.rb", "spec/other_spec.rb"]
        end
        allow(diff_analyzer).to receive(:head_sha).and_return(nil)
        allow(subject_resolver).to receive(:resolve_from_files) do |paths|
          calls << paths
          []
        end
        allow(mutant_generator).to receive(:generate).and_return([])
        allow(static_filter).to receive(:apply).and_return([])
        allow(execution_engine).to receive(:run).and_return([])
        allow(Henitai::Result).to receive(:new).and_return(result)
        allow(Henitai::Reporter).to receive(:run_all)

        runner.run

        expect(calls).to eq(
          [
            { from: "HEAD~1", to: "HEAD" },
            ["lib/sample.rb"]
          ]
        )
      end
    end
  end

  it "applies CLI subject patterns after resolving subjects" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib"))
      File.write(File.join(dir, "lib/sample.rb"), "class Sample; end\n")
      File.write(File.join(dir, "lib/other.rb"), "class Other; end\n")

      Dir.chdir(dir) do
        config = build_config(reporters: [])
        runner = described_class.new(
          config:,
          subjects: [Henitai::Subject.parse("Sample*")]
        )
        subject_resolver = instance_double(Henitai::SubjectResolver)
        mutant_generator = instance_double(Henitai::MutantGenerator)
        static_filter = instance_double(Henitai::StaticFilter)
        execution_engine = instance_double(Henitai::ExecutionEngine)
        integration = instance_double(Henitai::Integration::Rspec)
        history_store = build_history_store
        result = build_result([])
        alpha = build_subject("Sample#alpha", source_file: "lib/sample.rb")
        beta = build_subject("Sample#beta", source_file: "lib/sample.rb")
        other = build_subject("Other#gamma", source_file: "lib/other.rb")
        calls = []

        allow(runner).to receive_messages(
          subject_resolver:,
          mutant_generator:,
          static_filter:,
          execution_engine:,
          integration:,
          history_store:
        )
        allow(subject_resolver).to receive_messages(
          resolve_from_files: [alpha, beta, other],
          apply_pattern: [alpha, beta]
        )
        allow(integration).to receive(:select_tests).and_return([])
        allow(mutant_generator).to receive(:generate) do |selected_subjects, operators, kwargs|
          calls << [selected_subjects, operators.map(&:class), kwargs[:config]]
          []
        end
        allow(static_filter).to receive(:apply).and_return([])
        allow(execution_engine).to receive(:run).and_return([])
        allow(Henitai::Result).to receive(:new).and_return(result)
        allow(Henitai::Reporter).to receive(:run_all)

        runner.run

        expect(calls).to eq(
          [[
            [alpha, beta],
            Henitai::Operator.for_set(:light).map(&:class),
            config
          ]]
        )
      end
    end
  end

  it "expands normalized paths" do
    runner = described_class.new(config: build_config(reporters: []))

    expect(runner.send(:normalize_path, "lib/sample.rb")).to eq(File.expand_path("lib/sample.rb"))
  end

  it "returns configured thresholds when available" do
    runner = described_class.new(config: build_config(reporters: []))

    expect(runner.send(:result_thresholds)).to eq(low: 60, high: 80)
  end

  it "treats missing dirty worktree files as dirty source files" do
    runner = described_class.new(config: build_config(reporters: []))

    expect(runner.send(:dirty_source_files?, nil)).to be(true)
  end

  it "builds a survivor test filter with the default dirty_source_files flag" do
    runner = described_class.new(config: build_config(reporters: []))
    loaded = build_loaded_survivors([])
    filter = instance_double(Henitai::SurvivorTestFilter)
    diff_analyzer = instance_double(Henitai::GitDiffAnalyzer)

    allow(runner).to receive_messages(
      git_diff_analyzer: diff_analyzer,
      dirty_worktree_changed_files: []
    )
    allow(Henitai::SurvivorTestFilter).to receive(:new).and_return(filter)

    runner.send(:test_filter, loaded)

    expect(Henitai::SurvivorTestFilter).to have_received(:new).with(
      coverage_map: {},
      git_sha: "deadbeef",
      dirty_source_files: false,
      worktree_changed_files: [],
      diff_analyzer: diff_analyzer
    )
  end

  it "finalizes rerun survivors and records drift stats" do
    Dir.mktmpdir do |dir|
      report_path = File.join(dir, "mutation-report.json")
      File.write(report_path, "{}")

      runner = described_class.new(config: build_config(reporters: []), survivors_from: report_path)
      loaded = build_loaded_survivors(["stable-id"], coverage_map: { "lib/sample.rb" => [1] })
      selector = instance_double(
        Henitai::SurvivorSelector,
        drift_warning?: true,
        unmatched_ids: ["missing-id"]
      )
      selected = [build_mutant_status]
      stable = build_mutant_status
      pending = build_mutant_status
      filter = instance_double(Henitai::SurvivorTestFilter, apply: { stable: [stable], pending: [pending] })
      loader = instance_double(Henitai::SurvivorLoader, load: loaded)

      allow(Henitai::SurvivorLoader).to receive(:new).and_return(loader)
      allow(Henitai::SurvivorSelector).to receive(:new).and_return(selector)
      allow(runner).to receive(:test_filter).and_return(filter)
      allow(selector).to receive(:select).and_return(selected)

      warned = false
      allow(runner).to receive(:warn) { warned = true }

      result = runner.send(:apply_survivor_selection, [build_mutant_status])
      stats = runner.instance_variable_get(:@survivor_stats)

      expect(result).to eq([stable, pending])
      expect(stable.status).to eq(:survived)
      expect(warned).to be(true)
      expect(stats).to eq(
        matched: 1,
        unmatched_count: 1,
        unmatched_ids: ["missing-id"],
        skipped_count: 1,
        drift_warning: true
      )
    end
  end

  describe "cached activation recipes" do
    let(:tmpdir) { Dir.mktmpdir }
    after { FileUtils.rm_rf(tmpdir) }

    let(:report_path) do
      path = File.join(tmpdir, "mutation-report.json")
      File.write(path, JSON.generate(
        "schemaVersion" => "1.0",
        "files" => { "lib/sample.rb" => { "language" => "ruby", "source" => "", "mutants" => [] } }
      ))
      path
    end

    let(:runner)   { described_class.new(config: build_config(reporters: []), survivors_from: report_path) }
    let(:loaded)   { build_loaded_survivors(["deadbeef"], coverage_map: { "lib/sample.rb" => [1] }) }
    let(:selector) { instance_double(Henitai::SurvivorSelector, drift_warning?: false, unmatched_ids: []) }
    let(:loader)   { instance_double(Henitai::SurvivorLoader, load: loaded) }
    let(:base_recipe) do
      {
        "activationSource" => "define_method(:value) do\n  2\nend\n",
        "namespace"        => "Sample",
        "methodName"       => "value",
        "sourceFile"       => "lib/sample.rb",
        "operator"         => "ArithmeticOperator",
        "description"      => "+ to -",
        "location"         => {
          "file" => "lib/sample.rb", "startLine" => 1, "endLine" => 1, "startCol" => 0, "endCol" => 5
        }
      }
    end

    # Override recipe and filter per context
    let(:recipe) { base_recipe }
    let(:filter) { instance_double(Henitai::SurvivorTestFilter, apply: { stable: [build_mutant_status], pending: [] }) }

    before do
      @selected_stubs = nil
      allow(Henitai::SurvivorLoader).to receive(:new).and_return(loader)
      allow(Henitai::SurvivorActivationCache).to receive(:load).and_return("deadbeef" => recipe)
      allow(Henitai::SurvivorSelector).to receive(:new).and_return(selector)
      allow(selector).to receive(:select) do |stubs|
        @selected_stubs = stubs
        stubs
      end
      allow(runner).to receive(:test_filter).and_return(filter)
    end

    context "when recipe includes methodType" do
      let(:stable) { build_mutant_status }
      let(:recipe) { base_recipe.merge("methodType" => "class", "coveredBy" => ["spec/sample_spec.rb"]) }
      let(:filter) { instance_double(Henitai::SurvivorTestFilter, apply: { stable: [stable], pending: [] }) }

      it "maps methodType to symbol on the stub subject" do
        result = runner.send(:try_recipe_run)
        stub = @selected_stubs.first

        expect(result).to eq([stable])
        expect(stub.subject.method_type).to eq(:class)
        expect(stub.covered_by).to eq(["spec/sample_spec.rb"])
        expect(stub.location).to eq(
          file: "lib/sample.rb", start_line: 1, end_line: 1, start_col: 0, end_col: 5
        )
      end
    end

    context "when recipe omits methodType" do
      it "defaults method_type to :instance" do
        runner.send(:try_recipe_run)
        expect(@selected_stubs.first.subject.method_type).to eq(:instance)
      end
    end
  end

  describe "recipe fast path" do
    it "skips mutant generation when all survivors have cached activation recipes" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "lib"))
        File.write(File.join(dir, "lib/sample.rb"), "class Sample; end\n")

        report_path = File.join(dir, "mutation-report.json")
        stable_id   = "deadbeef" * 8

        File.write(report_path, JSON.generate(
                                  "schemaVersion" => "1.0",
                                  "files" => {
                                    "lib/sample.rb" => {
                                      "language" => "ruby", "source" => "",
                                      "mutants" => [{
                                        "stableId" => stable_id,
                                        "status" => "Survived"
                                      }]
                                    }
                                  }
                                ))

        recipe = {
          "activationSource" => "define_method(:value) do\n  nil\nend\n",
          "namespace" => "Sample",
          "methodName" => "value",
          "methodType" => "instance",
          "sourceFile" => "lib/sample.rb",
          "operator" => "ArithmeticOperator",
          "description" => "+ to -",
          "location" => { "file" => "lib/sample.rb", "startLine" => 1,
                          "endLine" => 1, "startCol" => 0, "endCol" => 5 },
          "coveredBy" => []
        }
        recipe_path = File.join(dir, Henitai::SurvivorActivationCache::FILENAME)
        File.write(recipe_path, JSON.generate({ stable_id => recipe }))

        Dir.chdir(dir) do
          config          = build_config(reporters: [])
          result          = build_result([])
          execution_engine = instance_double(Henitai::ExecutionEngine)
          integration      = instance_double(Henitai::Integration::Rspec)
          history_store    = build_history_store
          mutant_generator = instance_spy(Henitai::MutantGenerator)
          diff_analyzer    = instance_double(Henitai::GitDiffAnalyzer)

          runner = described_class.new(config:, survivors_from: report_path)
          allow(runner).to receive_messages(
            execution_engine:,
            integration:,
            history_store:,
            git_diff_analyzer: diff_analyzer
          )
          allow(diff_analyzer).to receive_messages(
            changed_files: [],
            head_sha: nil,
            working_tree_changed_files: []
          )
          allow(execution_engine).to receive(:run).and_return([])
          allow(Henitai::Result).to receive(:new).and_return(result)
          allow(Henitai::Reporter).to receive(:run_all)

          runner.run

          # The mutant generator must NOT have been called (fast path taken)
          expect(mutant_generator).not_to have_received(:generate)
        end
      end
    end

    it "falls back to the normal generation path when the recipe file is absent" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "lib"))
        File.write(File.join(dir, "lib/sample.rb"), "class Sample; end\n")

        report_path = File.join(dir, "mutation-report.json")
        File.write(report_path, JSON.generate(
                                  "schemaVersion" => "1.0",
                                  "files" => {
                                    "lib/sample.rb" => {
                                      "language" => "ruby", "source" => "",
                                      "mutants" => []
                                    }
                                  }
                                ))

        Dir.chdir(dir) do
          config           = build_config(reporters: [])
          result           = build_result([])
          execution_engine = instance_double(Henitai::ExecutionEngine)
          integration      = instance_double(Henitai::Integration::Rspec)
          history_store    = build_history_store
          mutant_generator = instance_double(Henitai::MutantGenerator)
          static_filter    = instance_double(Henitai::StaticFilter)
          subject_resolver = instance_double(Henitai::SubjectResolver)
          diff_analyzer    = instance_double(Henitai::GitDiffAnalyzer)

          runner = described_class.new(config:, survivors_from: report_path)
          allow(runner).to receive_messages(
            execution_engine:,
            integration:,
            history_store:,
            mutant_generator:,
            static_filter:,
            subject_resolver:,
            git_diff_analyzer: diff_analyzer
          )
          allow(diff_analyzer).to receive_messages(
            head_sha: nil,
            working_tree_changed_files: []
          )
          allow(subject_resolver).to receive(:resolve_from_files).and_return([])
          allow(mutant_generator).to receive(:generate).and_return([])
          allow(static_filter).to receive(:apply) { |m, _| m }
          allow(execution_engine).to receive(:run).and_return([])
          allow(Henitai::Result).to receive(:new).and_return(result)
          allow(Henitai::Reporter).to receive(:run_all)

          runner.run

          # The normal generation pipeline was invoked
          expect(mutant_generator).to have_received(:generate)
        end
      end
    end
  end

  describe "survivors_from:" do
    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def setup_runner_doubles(runner, _config, result)
      subject_resolver = instance_double(Henitai::SubjectResolver)
      mutant_generator = instance_double(Henitai::MutantGenerator)
      static_filter    = instance_double(Henitai::StaticFilter)
      execution_engine = instance_double(Henitai::ExecutionEngine)
      integration      = instance_double(Henitai::Integration::Rspec)
      history_store    = build_history_store

      allow(runner).to receive_messages(
        subject_resolver:, mutant_generator:, static_filter:,
        execution_engine:, integration:, history_store:
      )
      allow(subject_resolver).to receive(:resolve_from_files).and_return([])
      allow(mutant_generator).to receive(:generate).and_return([])
      allow(static_filter).to receive(:apply) { |m, _| m }
      allow(execution_engine).to receive(:run).and_return([])
      allow(Henitai::Result).to receive(:new).and_return(result)
      allow(Henitai::Reporter).to receive(:run_all)
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    it "marks the result as a partial rerun when survivors_from is given" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "lib"))
        File.write(File.join(dir, "lib/sample.rb"), "class Sample; end\n")
        report_path = File.join(dir, "mutation-report.json")
        File.write(report_path, JSON.generate(
                                  "schemaVersion" => "1.0",
                                  "files" => { "lib/sample.rb" => { "language" => "ruby", "source" => "",
                                                                    "mutants" => [] } }
                                ))

        Dir.chdir(dir) do
          config = build_config(reporters: [])
          result = instance_double(Henitai::Result, partial_rerun?: true)
          runner = described_class.new(config:, survivors_from: report_path)
          setup_runner_doubles(runner, config, result)

          runner.run

          expect(Henitai::Result).to have_received(:new).with(
            hash_including(partial_rerun: true)
          )
        end
      end
    end

    it "does not mark the result as partial rerun for normal runs" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "lib"))
        File.write(File.join(dir, "lib/sample.rb"), "class Sample; end\n")

        Dir.chdir(dir) do
          config = build_config(reporters: [])
          result = instance_double(Henitai::Result, partial_rerun?: false)
          runner = described_class.new(config:)
          setup_runner_doubles(runner, config, result)

          runner.run

          expect(Henitai::Result).to have_received(:new).with(
            hash_including(partial_rerun: false)
          )
        end
      end
    end
  end
end
# rubocop:enable RSpec/ExampleLength
