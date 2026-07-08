# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations

require "fileutils"
require "json"
require "parser/current"
require "spec_helper"
require "stringio"
require "tmpdir"

RSpec.describe Henitai::Runner do
  before do
    stub_const(
      "RunnerSpecConfig",
      Struct.new(
        :includes,
        :excludes,
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

  it "loads configuration by default" do
    config = build_config(reporters: [])
    allow(Henitai::Configuration).to receive(:load).and_return(config)

    runner = described_class.new

    expect(runner.config).to be(config)
    expect(Henitai::Configuration).to have_received(:load)
  end

  def build_config(overrides = {})
    values = default_config_values.merge(overrides)

    RunnerSpecConfig.new(
      values[:includes],
      values[:excludes],
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
      excludes: [],
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

  def build_schema_mutant(file:, status:, source: "1 + 2")
    node = Parser::CurrentRuby.parse(source)
    mutant = Henitai::Mutant.new(
      subject: build_subject("Sample#answer", source_file: file),
      operator: "ArithmeticOperator",
      nodes: { original: node, mutated: node },
      description: "replaced + with -",
      location: { file:, start_line: 1, end_line: 1, start_col: 0, end_col: 5 }
    )
    mutant.status = status
    mutant
  end

  # A mutant carrying a real status plus the predicates Result derives counts
  # from, so the pipeline can be asserted on the produced Result rather than on
  # an internal call log.
  def executed_mutant(status)
    Struct.new(:status) do
      def killed?   = status == :killed
      def survived? = status == :survived
    end.new(status)
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

  # Stubs only the true infrastructure seams (subject resolution, generation,
  # static filtering, the backgrounded coverage bootstrap, mutant execution,
  # integration and history persistence). Result and Reporter are left real so
  # examples can assert on observable output. The backgrounded bootstrap thread
  # is exercised for real; its join synchronizes the pipeline without sleeps.
  def stub_pipeline(runner, history_store:, resolved: [], generated: [], executed: [])
    subject_resolver = instance_double(Henitai::SubjectResolver, resolve_from_files: resolved)
    mutant_generator = instance_double(Henitai::MutantGenerator, generate: generated)
    static_filter = instance_double(Henitai::StaticFilter, apply: generated)
    coverage_bootstrapper = instance_double(Henitai::CoverageBootstrapper, ensure!: nil)
    execution_engine = instance_double(Henitai::ExecutionEngine, run: executed)
    integration = instance_double(Henitai::Integration::Rspec)

    allow(runner).to receive_messages(
      subject_resolver:, mutant_generator:, static_filter:,
      coverage_bootstrapper:, execution_engine:, integration:, history_store:
    )
  end

  describe "public collaborator seams" do
    it "builds a result through the public lazy constructors" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "lib"))
        File.write(File.join(dir, "lib/sample.rb"), "class Sample; end\n")

        Dir.chdir(dir) do
          config = build_config(reporters: [], reports_dir: File.join(dir, "reports"))
          runner = described_class.new(config:)
          subject = build_subject("Sample#answer", source_file: "lib/sample.rb")
          mutant = build_schema_mutant(file: "lib/sample.rb", status: :killed)
          subject_resolver = instance_double(Henitai::SubjectResolver)
          mutant_generator = instance_double(Henitai::MutantGenerator)
          static_filter = instance_double(Henitai::StaticFilter)
          execution_engine = instance_double(Henitai::ExecutionEngine)
          integration = instance_double(Henitai::Integration::Rspec)
          diff_analyzer = instance_double(Henitai::GitDiffAnalyzer, head_sha: "abc123")
          history_store = Henitai::MutantHistoryStore.new(
            path: File.join(dir, "reports", Henitai::HISTORY_STORE_FILENAME)
          )
          integration_class = class_double(Henitai::Integration::Rspec)

          allow(integration_class).to receive(:new).and_return(integration)
          allow(Henitai::Integration).to receive(:for).and_return(integration_class)
          allow(Henitai::SubjectResolver).to receive(:new).and_return(subject_resolver)
          allow(Henitai::MutantGenerator).to receive(:new).and_return(mutant_generator)
          allow(Henitai::StaticFilter).to receive(:new).and_return(static_filter)
          allow(Henitai::ExecutionEngine).to receive(:new).and_return(execution_engine)
          allow(Henitai::GitDiffAnalyzer).to receive(:new).and_return(diff_analyzer)
          allow(Henitai::MutantHistoryStore).to receive(:new).and_return(history_store)
          allow(subject_resolver).to receive(:resolve_from_files).and_return([subject])
          allow(mutant_generator).to receive(:generate).and_return([mutant])
          allow(static_filter).to receive(:apply).and_return([mutant])
          allow(execution_engine).to receive(:run).and_return([mutant])
          allow(Henitai::Reporter).to receive(:run_all)

          result = runner.run
          schema = result.to_stryker_schema

          expect(
            git_sha: result.git_sha,
            thresholds: result.thresholds,
            partial_rerun: result.partial_rerun?,
            survivor_stats: result.survivor_stats,
            source: schema[:files]["lib/sample.rb"][:source],
            total_mutants: history_store.trend_report[:runs].first[:totalMutants]
          ).to eq(
            git_sha: "abc123",
            thresholds: { high: 80, low: 60 },
            partial_rerun: false,
            survivor_stats: nil,
            source: "class Sample; end\n",
            total_mutants: 1
          )
        end
      end
    end

    it "returns an empty source string and nil git sha when the run cannot read source" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "lib"))
        File.write(File.join(dir, "lib/sample.rb"), "class Sample; end\n")

        Dir.chdir(dir) do
          config = build_config(
            reporters: [],
            reports_dir: File.join(dir, "reports")
          )
          runner = described_class.new(config:, mode: { dry_run: true })
          mutant = build_schema_mutant(file: "lib/missing.rb", status: :pending)
          subject_resolver = instance_double(Henitai::SubjectResolver)
          mutant_generator = instance_double(Henitai::MutantGenerator)
          static_filter = instance_double(Henitai::StaticFilter)
          diff_analyzer = instance_double(Henitai::GitDiffAnalyzer)
          dry_run_reporter = instance_double(Henitai::Reporter::DryRun, report: nil)

          allow(Henitai::SubjectResolver).to receive(:new).and_return(subject_resolver)
          allow(Henitai::MutantGenerator).to receive(:new).and_return(mutant_generator)
          allow(Henitai::StaticFilter).to receive(:new).and_return(static_filter)
          allow(Henitai::GitDiffAnalyzer).to receive(:new).and_return(diff_analyzer)
          allow(subject_resolver).to receive(:resolve_from_files).and_return([])
          allow(mutant_generator).to receive(:generate).and_return([mutant])
          allow(static_filter).to receive(:apply).and_return([mutant])
          allow(diff_analyzer).to receive(:head_sha).and_raise(StandardError)
          allow(Henitai::Reporter).to receive(:run_all)
          allow(Henitai::Reporter::DryRun).to receive(:new).and_return(dry_run_reporter)

          result = runner.run
          schema = result.to_stryker_schema

          expect(
            git_sha: result.git_sha,
            thresholds: result.thresholds,
            partial_rerun: result.partial_rerun?,
            source: schema[:files]["lib/missing.rb"][:source]
          ).to eq(
            git_sha: nil,
            thresholds: { high: 80, low: 60 },
            partial_rerun: false,
            source: ""
          )
        end
      end
    end

    it "uses the survivor rerun strategy through the public runner path" do
      Dir.mktmpdir do |dir|
        report_path = File.join(dir, "mutation-report.json")
        File.write(report_path, "{}")

        Dir.chdir(dir) do
          config = build_config(reporters: [], reports_dir: File.join(dir, "reports"))
          runner = described_class.new(config:, survivors_from: report_path)
          mutant = build_schema_mutant(file: "lib/sample.rb", status: :survived)
          subject_resolver = instance_double(Henitai::SubjectResolver)
          mutant_generator = instance_double(Henitai::MutantGenerator)
          static_filter = instance_double(Henitai::StaticFilter)
          execution_engine = instance_double(Henitai::ExecutionEngine)
          integration = instance_double(Henitai::Integration::Rspec)
          diff_analyzer = instance_double(Henitai::GitDiffAnalyzer, head_sha: "deadbeef")
          history_store = Henitai::MutantHistoryStore.new(
            path: File.join(dir, "reports", Henitai::HISTORY_STORE_FILENAME)
          )
          strategy = instance_double(Henitai::SurvivorRerunStrategy)
          integration_class = class_double(Henitai::Integration::Rspec)

          allow(integration_class).to receive(:new).and_return(integration)
          allow(Henitai::Integration).to receive(:for).and_return(integration_class)
          allow(Henitai::GitDiffAnalyzer).to receive(:new).and_return(diff_analyzer)
          allow(Henitai::SurvivorRerunStrategy).to receive(:new).and_return(strategy)
          allow(Henitai::SubjectResolver).to receive(:new).and_return(subject_resolver)
          allow(Henitai::MutantGenerator).to receive(:new).and_return(mutant_generator)
          allow(Henitai::StaticFilter).to receive(:new).and_return(static_filter)
          allow(Henitai::ExecutionEngine).to receive(:new).and_return(execution_engine)
          allow(Henitai::MutantHistoryStore).to receive(:new).and_return(history_store)
          allow(strategy).to receive_messages(
            try_recipe_run: [mutant],
            survivor_stats: {
              matched: 1,
              unmatched_count: 0,
              unmatched_ids: [],
              skipped_count: 0,
              drift_warning: false
            }
          )
          allow(execution_engine).to receive(:run).and_return([mutant])
          allow(Henitai::Reporter).to receive(:run_all)

          result = runner.run

          expect(
            partial_rerun: result.partial_rerun?,
            survivor_stats: result.survivor_stats,
            git_sha: result.git_sha
          ).to eq(
            partial_rerun: true,
            survivor_stats: {
              matched: 1,
              unmatched_count: 0,
              unmatched_ids: [],
              skipped_count: 0,
              drift_warning: false
            },
            git_sha: "deadbeef"
          )
        end
      end
    end
  end

  # Behavioral pipeline test: real Result, real Reporter dispatch suppressed,
  # infra seams stubbed. We assert on the produced Result (the runner's output)
  # rather than on the order in which collaborators were called. The kill/
  # survive mix the execution engine returns must flow through to the Result's
  # reported counts and mutation score, and the same Result must be reported.
  describe "dry run" do
    def capture_stdout
      original_stdout = $stdout
      stdout = StringIO.new
      $stdout = stdout
      yield
      stdout.string
    ensure
      $stdout = original_stdout
    end

    def dry_run_mutant(status)
      Struct.new(:subject, :status, :operator, :description, :location) do
        def killed?   = false
        def survived? = false
      end.new(
        Struct.new(:expression).new("Sample#answer"),
        status,
        :ArithmeticOperator,
        "replaced + with -",
        { file: "lib/sample.rb", start_line: 3, end_line: 3 }
      )
    end

    def stub_dry_run_pipeline(runner, generated:)
      subject_resolver = instance_double(Henitai::SubjectResolver, resolve_from_files: [])
      mutant_generator = instance_double(Henitai::MutantGenerator, generate: generated)
      static_filter = instance_double(Henitai::StaticFilter, apply: generated)
      coverage_bootstrapper = instance_double(Henitai::CoverageBootstrapper, ensure!: nil)
      # Strict doubles with no stubbed methods: any execution or history
      # write during a dry run fails the example.
      execution_engine = instance_double(Henitai::ExecutionEngine)
      history_store = instance_double(Henitai::MutantHistoryStore)

      allow(runner).to receive_messages(
        subject_resolver:, mutant_generator:, static_filter:,
        coverage_bootstrapper:, execution_engine:, integration: nil, history_store:
      )
    end

    it "lists the post-filter mutants without executing, persisting or reporting" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "lib"))
        File.write(File.join(dir, "lib/sample.rb"), "class Sample; end\n")

        Dir.chdir(dir) do
          reports_dir = File.join(dir, "reports")
          runner = described_class.new(config: build_config(reports_dir:), mode: { dry_run: true })
          mutants = [dry_run_mutant(:pending), dry_run_mutant(:ignored)]
          stub_dry_run_pipeline(runner, generated: mutants)
          started_at = Time.at(10)
          finished_at = Time.at(20)
          allow(Time).to receive(:now).and_return(started_at, finished_at)
          run_all_called = false
          allow(Henitai::Reporter).to receive(:run_all) { run_all_called = true }

          output = capture_stdout { runner.run }

          expect(
            listing: output.include?("Dry run: 2 mutants") &&
              output.include?("[pending]") && output.include?("[ignored]"),
            result_mutants: runner.result.mutants,
            configured_reporters_run: run_all_called,
            reports_dir_written: Dir.exist?(reports_dir) && !Dir.empty?(reports_dir)
          ).to eq(
            listing: true,
            result_mutants: mutants,
            configured_reporters_run: false,
            reports_dir_written: false
          )
          expect(runner.result.started_at).to eq(started_at)
          expect(runner.result.finished_at).to eq(finished_at)
        end
      end
    end
  end

  describe "incremental verdict reuse" do
    it "routes the filtered mutants through the incremental filter when enabled" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "lib"))
        File.write(File.join(dir, "lib/sample.rb"), "class Sample; end\n")

        Dir.chdir(dir) do
          runner = described_class.new(config: build_config(reporters: []), mode: { incremental: true })
          generated = [executed_mutant(:killed)]
          history_store = build_history_store
          stub_pipeline(runner, history_store:, generated:, executed: generated)
          allow(Henitai::Reporter).to receive(:run_all)

          filter = instance_double(Henitai::IncrementalFilter)
          captured_store = nil
          apply_calls = 0
          allow(Henitai::IncrementalFilter).to receive(:new) do |history_store:|
            captured_store = history_store
            filter
          end
          allow(filter).to receive(:apply) do |mutants|
            apply_calls += 1
            mutants
          end

          runner.run

          expect([captured_store, apply_calls]).to eq([history_store, 1])
        end
      end
    end

    it "never builds the incremental filter on the default path" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "lib"))
        File.write(File.join(dir, "lib/sample.rb"), "class Sample; end\n")

        Dir.chdir(dir) do
          runner = described_class.new(config: build_config(reporters: []))
          stub_pipeline(runner, history_store: build_history_store)
          allow(Henitai::Reporter).to receive(:run_all)
          allow(Henitai::IncrementalFilter).to receive(:new)

          runner.run

          expect(Henitai::IncrementalFilter).not_to have_received(:new)
        end
      end
    end
  end

  it "returns a Result whose counts reflect the executed mutants" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib"))
      File.write(File.join(dir, "lib/sample.rb"), "class Sample; end\n")

      Dir.chdir(dir) do
        runner = described_class.new(config: build_config)
        subject = build_subject("Sample#answer", source_file: "lib/sample.rb")
        executed = [executed_mutant(:killed), executed_mutant(:killed), executed_mutant(:survived)]
        history_store = build_history_store
        reported = nil

        stub_pipeline(
          runner,
          history_store:,
          resolved: [subject],
          generated: executed,
          executed:
        )
        reported_names = nil
        allow(Henitai::Reporter).to receive(:run_all) do |kwargs|
          reported = kwargs[:result]
          reported_names = kwargs[:names]
        end

        result = runner.run

        expect(
          returned: result.equal?(runner.result),
          reported: reported.equal?(result),
          killed: result.killed,
          survived: result.survived,
          score: result.mutation_score,
          reporters: reported_names
        ).to eq(
          returned: true, reported: true, killed: 2, survived: 1, score: 66.67,
          reporters: runner.config.reporters
        )
      end
    end
  end

  it "records the result in the history store and stamps run timing" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib"))
      File.write(File.join(dir, "lib/sample.rb"), "class Sample; end\n")

      Dir.chdir(dir) do
        runner = described_class.new(config: build_config(reporters: []))
        recorded = nil
        history_store = instance_double(Henitai::MutantHistoryStore)
        allow(history_store).to receive(:record) { |result, **| recorded = result }

        stub_pipeline(runner, history_store:, executed: [executed_mutant(:killed)])
        allow(Henitai::Reporter).to receive(:run_all)

        result = runner.run

        expect(
          recorded: recorded.equal?(result),
          timed: result.finished_at >= result.started_at
        ).to eq(recorded: true, timed: true)
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

  it "drops files matched by excludes globs from the source set" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib"))
      File.write(File.join(dir, "lib/sample.rb"), "class Sample; end\n")
      File.write(File.join(dir, "lib/eager_load.rb"), "# loader\n")

      Dir.chdir(dir) do
        config = build_config(reporters: [], excludes: ["lib/eager_load.rb"])
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

        expect(calls).to eq([["lib/sample.rb"]])
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
        config = build_config(reporters: [:terminal])
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

  it "passes the config to the static filter" do
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
        received_config = nil

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
        allow(static_filter).to receive(:apply) do |mutants, received|
          received_config = received
          mutants
        end
        allow(execution_engine).to receive(:run).and_return([])
        allow(Henitai::Result).to receive(:new).and_return(result)
        allow(Henitai::Reporter).to receive(:run_all)

        runner.run

        expect(received_config).to be(config)
      end
    end
  end

  it "passes nil thresholds when the config does not expose them" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib"))
      File.write(File.join(dir, "lib/sample.rb"), "class Sample; end\n")

      Dir.chdir(dir) do
        config = Struct.new(
          :includes,
          :excludes,
          :operators,
          :timeout,
          :reporters,
          :integration,
          :reports_dir
        ).new(["lib"], [], :light, 10.0, [], "rspec", "reports")
        runner = described_class.new(config:)
        subject_resolver = instance_double(Henitai::SubjectResolver)
        mutant_generator = instance_double(Henitai::MutantGenerator)
        static_filter = instance_double(Henitai::StaticFilter)
        execution_engine = instance_double(Henitai::ExecutionEngine)
        integration = instance_double(Henitai::Integration::Rspec)
        history_store = build_history_store
        result = build_result([])
        captured = nil

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
        allow(execution_engine).to receive(:run).and_return([])
        allow(Henitai::Result).to receive(:new) do |**kwargs|
          captured = kwargs
          result
        end
        allow(Henitai::Reporter).to receive(:run_all)

        runner.run

        expect(captured[:thresholds]).to be_nil
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

        allow(Henitai::GitDiffAnalyzer).to receive(:new).and_return(diff_analyzer)
        allow(runner).to receive_messages(
          subject_resolver:,
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
        allow(diff_analyzer).to receive(:head_sha).and_return("new-sha")
        allow(subject_resolver).to receive(:resolve_from_files) do |paths|
          calls << paths
          []
        end
        allow(mutant_generator).to receive(:generate).and_return([])
        allow(static_filter).to receive(:apply).and_return([])
        allow(execution_engine).to receive(:run).and_return([])
        captured = nil
        allow(Henitai::Result).to receive(:new) do |**kwargs|
          captured = kwargs
          result
        end
        allow(Henitai::Reporter).to receive(:run_all)

        runner.run

        expect(Henitai::GitDiffAnalyzer).to have_received(:new)
        expect(captured[:git_sha]).to eq("new-sha")
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
        allow(subject_resolver).to receive(:resolve_from_files).and_return([alpha, beta, other])
        pattern_calls = []
        allow(subject_resolver).to receive(:apply_pattern) do |subjects, expression|
          pattern_calls << [subjects, expression]
          [alpha, beta, alpha]
        end
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

        expect(pattern_calls).to eq([[[alpha, beta, other], "Sample*"]])
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

  it "finalizes rerun survivors and records drift stats" do
    Dir.mktmpdir do |dir|
      report_path = File.join(dir, "mutation-report.json")
      File.write(report_path, "{}")

      diff_analyzer = instance_double(
        Henitai::GitDiffAnalyzer,
        working_tree_changed_files: [],
        changed_files: []
      )
      strategy = Henitai::SurvivorRerunStrategy.new(
        survivors_from: report_path,
        config: build_config(reporters: []),
        git_diff_analyzer: diff_analyzer
      )
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
      allow(strategy).to receive(:test_filter).and_return(filter)
      allow(selector).to receive(:select).and_return(selected)

      warned = false
      allow(strategy).to receive(:warn) { warned = true }

      result = strategy.apply_selection([build_mutant_status])
      stats = strategy.survivor_stats

      expect(
        result: result,
        stable_status: stable.status,
        warned: warned,
        stats: stats
      ).to eq(
        result: [stable, pending],
        stable_status: :survived,
        warned: true,
        stats: {
          matched: 1,
          unmatched_count: 1,
          unmatched_ids: ["missing-id"],
          skipped_count: 1,
          drift_warning: true
        }
      )
    end
  end

  describe "cached activation recipes" do
    def base_recipe
      {
        "activationSource" => "define_method(:value) do\n  2\nend\n",
        "namespace" => "Sample",
        "methodName" => "value",
        "sourceFile" => "lib/sample.rb",
        "operator" => "ArithmeticOperator",
        "description" => "+ to -",
        "location" => {
          "file" => "lib/sample.rb", "startLine" => 1, "endLine" => 1, "startCol" => 0, "endCol" => 5
        }
      }
    end

    let(:tmpdir) { Dir.mktmpdir }
    let(:report_path) do
      path = File.join(tmpdir, "mutation-report.json")
      File.write(
        path,
        JSON.generate(
          "schemaVersion" => "1.0",
          "files" => {
            "lib/sample.rb" => { "language" => "ruby", "source" => "", "mutants" => [] }
          }
        )
      )
      path
    end
    let(:recipe) { base_recipe }
    let(:setup) do
      loaded = build_loaded_survivors(["deadbeef"], coverage_map: { "lib/sample.rb" => [1] }, git_sha: nil)
      selector = instance_double(Henitai::SurvivorSelector, drift_warning?: false, unmatched_ids: [])
      loader = instance_double(Henitai::SurvivorLoader, load: loaded)
      stable = build_mutant_status
      filter = instance_double(Henitai::SurvivorTestFilter, apply: { stable: [stable], pending: [] })
      strategy = Henitai::SurvivorRerunStrategy.new(
        survivors_from: report_path,
        config: build_config(reporters: []),
        git_diff_analyzer: instance_double(Henitai::GitDiffAnalyzer)
      )
      selected_stubs = nil

      allow(Henitai::SurvivorLoader).to receive(:new).and_return(loader)
      allow(Henitai::SurvivorActivationCache).to receive(:load) { { "deadbeef" => recipe } }
      allow(Henitai::SurvivorSelector).to receive(:new).and_return(selector)
      allow(selector).to receive(:select) do |stubs|
        selected_stubs = stubs
        stubs
      end
      allow(strategy).to receive_messages(
        dirty_worktree_changed_files: [],
        test_filter: filter
      )

      {
        strategy: strategy,
        stable: stable,
        selected_stubs: lambda {
          selected_stubs
        }
      }
    end

    after { FileUtils.rm_rf(tmpdir) }

    def strategy = setup.fetch(:strategy)
    def stable = setup.fetch(:stable)
    def selected_stubs = setup.fetch(:selected_stubs).call

    context "when recipe includes methodType" do
      let(:recipe) { base_recipe.merge("methodType" => "class", "coveredBy" => ["spec/sample_spec.rb"]) }

      it "maps methodType to symbol on the stub subject" do
        result = strategy.try_recipe_run
        stub = selected_stubs.first

        expect(
          result: result,
          method_type: stub.subject.method_type,
          covered_by: stub.covered_by,
          location: stub.location
        ).to eq(
          result: [stable],
          method_type: :class,
          covered_by: ["spec/sample_spec.rb"],
          location: {
            file: "lib/sample.rb", start_line: 1, end_line: 1, start_col: 0, end_col: 5
          }
        )
      end
    end

    context "when recipe omits methodType" do
      it "defaults method_type to :instance" do
        strategy.try_recipe_run
        expect(selected_stubs.first.subject.method_type).to eq(:instance)
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
          received_mutants = :unset

          runner = described_class.new(config:, survivors_from: report_path)
          allow(runner).to receive_messages(
            execution_engine:,
            integration:,
            history_store:,
            git_diff_analyzer: diff_analyzer
          )
          allow(runner).to receive(:source_files).and_raise(
            "source_files should not be called on the recipe fast path"
          )
          allow(diff_analyzer).to receive_messages(
            changed_files: [],
            head_sha: nil,
            working_tree_changed_files: []
          )
          allow(execution_engine).to receive(:run) do |mutants, _integration, _config, **_kwargs|
            received_mutants = mutants
            []
          end
          allow(Henitai::Result).to receive(:new).and_return(result)
          allow(Henitai::Reporter).to receive(:run_all)

          runner.run

          # The mutant generator must NOT have been called (fast path taken)
          expect(mutant_generator).not_to have_received(:generate)
          expect(received_mutants.map(&:stable_id)).to eq([stable_id])
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

    it "falls back to normal generation when source files changed since the report" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "lib"))
        File.write(File.join(dir, "lib/sample.rb"), "class Sample; end\n")

        report_path = File.join(dir, "mutation-report.json")
        stable_id   = "deadbeef" * 8
        File.write(report_path, JSON.generate(
                                  "schemaVersion" => "1.0",
                                  "gitSha" => "old-sha",
                                  "files" => {
                                    "lib/sample.rb" => {
                                      "language" => "ruby", "source" => "",
                                      "mutants" => [{ "stableId" => stable_id, "status" => "Survived" }]
                                    }
                                  }
                                ))
        recipe_path = File.join(dir, Henitai::SurvivorActivationCache::FILENAME)
        File.write(recipe_path, JSON.generate(
                                  stable_id => {
                                    "activationSource" => "define_method(:value) { nil }",
                                    "namespace" => "Sample",
                                    "methodName" => "value",
                                    "sourceFile" => "lib/sample.rb",
                                    "operator" => "ArithmeticOperator",
                                    "description" => "+ to -",
                                    "location" => { "file" => "lib/sample.rb", "startLine" => 1,
                                                    "endLine" => 1, "startCol" => 0, "endCol" => 5 },
                                    "coveredBy" => []
                                  }
                                ))

        Dir.chdir(dir) do
          config           = build_config(reporters: [])
          result           = build_result([])
          execution_engine = instance_double(Henitai::ExecutionEngine, run: [])
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
            changed_files: ["lib/sample.rb"],
            head_sha: "new-sha",
            working_tree_changed_files: []
          )
          allow(subject_resolver).to receive(:resolve_from_files).and_return([])
          allow(mutant_generator).to receive(:generate).and_return([])
          allow(static_filter).to receive(:apply) { |m, _| m }
          allow(Henitai::Result).to receive(:new).and_return(result)
          allow(Henitai::Reporter).to receive(:run_all)

          runner.run

          expect(mutant_generator).to have_received(:generate)
        end
      end
    end

    describe "recipe fast path validation" do
      it "skips mutant generation when all survivors have cached activation recipes and passes executed mutants" do # rubocop:disable RSpec/MultipleExpectations
        Dir.mktmpdir do |dir|
          FileUtils.mkdir_p(File.join(dir, "lib"))
          File.write(File.join(dir, "lib/sample.rb"), "class Sample; end\n")

          report_path = File.join(dir, "mutation-report.json")
          stable_id   = "deadbeef" * 8

          report_data = {
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
          }
          File.write(report_path, JSON.generate(report_data))

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

          original = Dir.pwd
          begin
            Dir.chdir(dir) do
              config = build_config(reporters: [])
              execution_engine = instance_double(Henitai::ExecutionEngine)
              integration = instance_double(Henitai::Integration::Rspec)
              history_store = build_history_store
              diff_analyzer = instance_double(Henitai::GitDiffAnalyzer)

              runner = described_class.new(config:, survivors_from: report_path)
              allow(runner).to receive_messages(
                execution_engine:,
                integration:,
                history_store:,
                git_diff_analyzer: diff_analyzer
              )
              allow(runner).to receive(:source_files).and_raise(
                "source_files should not be called on the recipe fast path"
              )
              allow(diff_analyzer).to receive_messages(
                changed_files: [],
                head_sha: nil,
                working_tree_changed_files: []
              )

              expected_mutants = [executed_mutant(:killed)]
              allow(execution_engine).to receive(:run).and_return(expected_mutants)
              allow(Henitai::Reporter).to receive(:run_all)
              allow(Henitai::Result).to receive(:new).and_call_original

              result = runner.run
              expect(result.mutants).to eq(expected_mutants)
              expect(Henitai::Result).to have_received(:new).with(
                hash_including(mutants: expected_mutants)
              )
            end
          ensure
            Dir.chdir(original)
          end
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

  describe "#initialize" do
    it "defaults config to Configuration.load when none is provided" do
      fake_config = instance_double(Henitai::Configuration)
      allow(Henitai::Configuration).to receive(:load).and_return(fake_config)
      runner = described_class.new
      expect(runner.config).to eq(fake_config)
    end
  end

  describe "#resolve_subjects" do
    it "defaults source_files to self.source_files" do # rubocop:disable RSpec/MultipleExpectations
      runner = described_class.new(config: build_config)
      resolver = instance_double(Henitai::SubjectResolver)
      allow(resolver).to receive(:resolve_from_files).with(["lib/sample.rb"]).and_return([])
      allow(runner).to receive_messages(
        source_files: ["lib/sample.rb"],
        subject_resolver: resolver
      )

      expect(runner.send(:resolve_subjects)).to eq([])
      expect(resolver).to have_received(:resolve_from_files).with(["lib/sample.rb"])
    end

    it "applies pattern on the resolver with the correct pattern expression" do # rubocop:disable RSpec/MultipleExpectations
      subject_pattern = double(expression: "Sample*")
      runner = described_class.new(config: build_config, subjects: [subject_pattern])
      resolver = instance_double(Henitai::SubjectResolver)

      subj = build_subject("Sample#answer", source_file: "lib/sample.rb")
      allow(resolver).to receive(:resolve_from_files).with(["lib/sample.rb"]).and_return([subj])
      allow(resolver).to receive(:apply_pattern).with([subj], "Sample*").and_return([subj])
      allow(runner).to receive_messages(
        source_files: ["lib/sample.rb"],
        subject_resolver: resolver
      )

      expect(runner.send(:resolve_subjects)).to eq([subj])
      expect(resolver).to have_received(:resolve_from_files).with(["lib/sample.rb"])
      expect(resolver).to have_received(:apply_pattern).with([subj], "Sample*")
    end
  end

  describe "#mutants_for" do
    it "calls static_filter.apply with the generated mutants and config" do # rubocop:disable RSpec/MultipleExpectations
      config = build_config(reporters: [])
      runner = described_class.new(config:)

      subject = build_subject("Sample#answer", source_file: "lib/sample.rb")
      mutants = [build_mutant(subject)]
      filtered = [build_mutant(subject)]

      static_filter = instance_double(Henitai::StaticFilter)
      allow(static_filter).to receive(:apply).with(mutants, config).and_return(filtered)
      allow(runner).to receive_messages(
        static_filter:,
        generate_mutants: mutants
      )

      fake_thread = instance_double(Thread, value: nil)
      allow(Thread).to receive(:new).and_return(fake_thread)

      expect(runner.send(:mutants_for, [subject], ["lib/sample.rb"])).to eq(filtered)
      expect(static_filter).to have_received(:apply).with(mutants, config)
      expect(Thread).to have_received(:new)
      expect(fake_thread).to have_received(:value)
    end

    it "applies survivor selection in survivor rerun" do # rubocop:disable RSpec/MultipleExpectations
      report_path = "reports/mutation-report.json"
      config = build_config(reporters: [])
      runner = described_class.new(config:, survivors_from: report_path)

      subject = build_subject("Sample#answer", source_file: "lib/sample.rb")
      mutants = [build_mutant(subject)]
      filtered = [build_mutant(subject)]
      selected = [build_mutant(subject)]

      static_filter = instance_double(Henitai::StaticFilter)
      allow(static_filter).to receive(:apply).and_return(filtered)

      strategy = instance_double(Henitai::SurvivorRerunStrategy)
      allow(strategy).to receive(:apply_selection).with(filtered).and_return(selected)
      allow(runner).to receive_messages(
        static_filter:,
        survivor_strategy: strategy,
        generate_mutants: mutants,
        bootstrap_mutants: instance_double(Thread, value: nil)
      )

      expect(runner.send(:mutants_for, [subject], ["lib/sample.rb"])).to eq(selected)
      expect(strategy).to have_received(:apply_selection).with(filtered)
    end
  end

  describe "#report and #progress_reporter" do
    it "calls Reporter.run_all with exact parameters" do
      config = build_config(reporters: ["terminal"])
      runner = described_class.new(config:)
      result = build_result([])
      history = instance_double(Henitai::MutantHistoryStore)
      allow(runner).to receive(:history_store).and_return(history)
      allow(Henitai::Reporter).to receive(:run_all)

      runner.send(:report, result)

      expect(Henitai::Reporter).to have_received(:run_all).with(
        names: ["terminal"],
        result:,
        config:,
        history_store: history
      )
    end

    it "returns a terminal reporter when reporters contains symbols" do
      config = build_config(reporters: [:terminal])
      runner = described_class.new(config:)
      expect(runner.send(:progress_reporter)).to be_a(Henitai::Reporter::Terminal)
    end
  end

  describe "#source_provider" do
    it "returns a lambda that reads files and caches their content" do # rubocop:disable RSpec/MultipleExpectations
      runner = described_class.new(config: build_config)
      provider = runner.send(:source_provider)
      expect(provider).to be_a(Proc)

      Dir.mktmpdir do |dir|
        file_path = File.join(dir, "test.txt")
        File.write(file_path, "hello world")

        expect(provider.call(file_path)).to eq("hello world")
        File.write(file_path, "changed")
        expect(provider.call(file_path)).to eq("hello world")

        expect(provider.call("nonexistent.txt")).to eq("")
      end
    end
  end

  describe "#safe_head_sha" do
    it "returns the git head SHA" do
      runner = described_class.new(config: build_config)
      analyzer = instance_double(Henitai::GitDiffAnalyzer, head_sha: "abc1234")
      allow(runner).to receive(:git_diff_analyzer).and_return(analyzer)
      expect(runner.send(:safe_head_sha)).to eq("abc1234")
    end

    it "returns nil and rescues StandardError when GitDiffAnalyzer fails" do
      runner = described_class.new(config: build_config)
      analyzer = instance_double(Henitai::GitDiffAnalyzer)
      allow(analyzer).to receive(:head_sha).and_raise(StandardError, "git failed")
      allow(runner).to receive(:git_diff_analyzer).and_return(analyzer)
      expect(runner.send(:safe_head_sha)).to be_nil
    end
  end

  describe "#git_diff_analyzer" do
    it "instantiates a GitDiffAnalyzer" do
      runner = described_class.new(config: build_config)
      expect(runner.send(:git_diff_analyzer)).to be_a(Henitai::GitDiffAnalyzer)
    end
  end

  describe "#unique_subjects" do
    it "keeps subjects with the same expression if they are in different source files" do
      runner = described_class.new(config: build_config)
      s1 = build_subject("Greeter#hello", source_file: "lib/foo.rb")
      s2 = build_subject("Greeter#hello", source_file: "lib/bar.rb")
      s3 = build_subject("Greeter#hello", source_file: "lib/foo.rb")

      unique = runner.send(:unique_subjects, [s1, s2, s3])
      expect(unique).to eq([s1, s2])
    end
  end

  describe "#result_thresholds" do
    it "returns nil when config does not respond to thresholds" do
      config = Object.new
      runner = described_class.new(config:)
      expect(runner.send(:result_thresholds)).to be_nil
    end

    it "returns config thresholds when config responds to thresholds" do
      config = build_config(thresholds: { low: 20, high: 80 })
      runner = described_class.new(config:)
      expect(runner.send(:result_thresholds)).to eq(low: 20, high: 80)
    end
  end

  describe "#reject_excluded" do
    it "returns the files immediately and does not normalize paths when excludes is empty" do # rubocop:disable RSpec/MultipleExpectations
      runner = described_class.new(config: build_config(excludes: []))
      allow(runner).to receive(:normalize_path).and_call_original

      expect(runner.send(:reject_excluded, ["lib/foo.rb"])).to eq(["lib/foo.rb"])
      expect(runner).not_to have_received(:normalize_path)
    end

    it "filters out excluded files by pattern" do
      runner = described_class.new(config: build_config(excludes: ["lib/exclude*"]))
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "lib"))
        File.write(File.join(dir, "lib/foo.rb"), "")
        File.write(File.join(dir, "lib/exclude_me.rb"), "")

        original = Dir.pwd
        begin
          Dir.chdir(dir) do
            files = ["lib/foo.rb", "lib/exclude_me.rb"]
            filtered = runner.send(:reject_excluded, files)
            expect(filtered).to eq(["lib/foo.rb"])
          end
        ensure
          Dir.chdir(original)
        end
      end
    end
  end

  describe "SurvivorRerunStrategy#dirty_source_files? (private)" do
    def strategy_with_analyzer(analyzer, includes: ["lib"])
      Henitai::SurvivorRerunStrategy.new(
        survivors_from: "reports/mutation-report.json",
        config: build_config(includes:),
        git_diff_analyzer: analyzer
      )
    end

    def stub_analyzer(committed: [])
      analyzer = instance_double(Henitai::GitDiffAnalyzer)
      allow(analyzer).to receive(:changed_files).with(from: anything, to: "HEAD").and_return(committed)
      analyzer
    end

    it "returns true when a committed source file in includes changed since git_sha" do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          strategy = strategy_with_analyzer(stub_analyzer(committed: ["lib/henitai/foo.rb"]))
          expect(strategy.send(:dirty_source_files?, [], git_sha: "abc123")).to be(true)
        end
      end
    end

    it "returns false when only spec files changed since git_sha" do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          strategy = strategy_with_analyzer(stub_analyzer(committed: ["spec/henitai/foo_spec.rb"]))
          expect(strategy.send(:dirty_source_files?, [], git_sha: "abc123")).to be(false)
        end
      end
    end

    it "returns false when git_sha is nil and worktree is clean" do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          strategy = strategy_with_analyzer(instance_double(Henitai::GitDiffAnalyzer))
          expect(strategy.send(:dirty_source_files?, [], git_sha: nil)).to be(false)
        end
      end
    end

    it "returns true when git diff raises (conservative fallback)" do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          analyzer = instance_double(Henitai::GitDiffAnalyzer)
          allow(analyzer).to receive(:changed_files).and_raise(Henitai::GitDiffError, "fatal")
          strategy = strategy_with_analyzer(analyzer)
          expect(strategy.send(:dirty_source_files?, [], git_sha: "abc123")).to be(true)
        end
      end
    end

    it "returns true when dirty_worktree_files is nil regardless of git_sha" do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          strategy = strategy_with_analyzer(instance_double(Henitai::GitDiffAnalyzer))
          expect(strategy.send(:dirty_source_files?, nil, git_sha: "abc123")).to be(true)
        end
      end
    end
  end
end
# rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
