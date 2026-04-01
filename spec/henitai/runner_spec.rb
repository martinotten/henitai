# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength

require "fileutils"
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
        :integration
      )
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
      values[:integration]
    )
  end

  def default_config_values
    {
      includes: ["lib"],
      operators: :light,
      timeout: 10.0,
      reporters: ["terminal"],
      thresholds: { low: 60, high: 80 },
      integration: "rspec"
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

  it "runs the pipeline and reports the result" do
    config = build_config
    runner = described_class.new(config:)
    subject = build_subject("Sample#answer", source_file: "lib/sample.rb")
    subjects = [subject]
    mutants = [build_mutant(subject)]
    result = build_result(mutants)
    calls = []
    subject_resolver = instance_double(Henitai::SubjectResolver)
    mutant_generator = instance_double(Henitai::MutantGenerator)
    static_filter = instance_double(Henitai::StaticFilter)
    execution_engine = instance_double(Henitai::ExecutionEngine)
    integration = instance_double(Henitai::Integration::Rspec)
    reporter = instance_double(Henitai::Reporter::Terminal)

    allow(runner).to receive_messages(
      source_files: ["lib/sample.rb"],
      subject_resolver:,
      mutant_generator:,
      static_filter:,
      execution_engine:,
      integration:,
      progress_reporter: reporter
    )
    allow(subject_resolver).to receive(:resolve_from_files) do |paths|
      calls << [:resolve_from_files, paths]
      subjects
    end
    allow(mutant_generator).to receive(:generate) do |resolved_subjects, operators, kwargs|
      calls << [:generate, resolved_subjects, operators.map(&:class), kwargs[:config]]
      mutants
    end
    allow(static_filter).to receive(:apply) do |current_mutants, received_config|
      calls << [:filter, current_mutants, received_config]
      mutants
    end
    allow(execution_engine).to receive(:run) do |current_mutants,
                                                 current_integration,
                                                 received_config,
                                                 progress_reporter:|
      calls << [
        :execute,
        current_mutants,
        current_integration,
        received_config,
        progress_reporter
      ]
      mutants
    end
    allow(Henitai::Result).to receive(:new) do |kwargs|
      calls << [
        :result,
        kwargs[:mutants],
        kwargs[:started_at].is_a?(Time),
        kwargs[:finished_at].is_a?(Time)
      ]
      result
    end
    allow(Henitai::Reporter).to receive(:run_all) do |kwargs|
      calls << [:report, kwargs]
    end

    runner.run

    expect(calls).to eq(
      [
        [:resolve_from_files, ["lib/sample.rb"]],
        [
          :generate,
          subjects,
          Henitai::Operator.for_set(:light).map(&:class),
          config
        ],
        [:filter, mutants, config],
        [:execute, mutants, integration, config, reporter],
        [
          :result,
          mutants,
          true,
          true
        ],
        [
          :report,
          {
            names: ["terminal"],
            result:,
            config:
          }
        ]
      ]
    )
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
        result = build_result([])
        calls = []

        allow(runner).to receive_messages(
          subject_resolver:,
          mutant_generator:,
          static_filter:,
          execution_engine:,
          integration:,
          progress_reporter: nil
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
        result = build_result([])
        calls = []

        allow(runner).to receive_messages(
          subject_resolver:,
          git_diff_analyzer: diff_analyzer,
          mutant_generator:,
          static_filter:,
          execution_engine:,
          integration:,
          progress_reporter: nil
        )
        allow(diff_analyzer).to receive(:changed_files) do |kwargs|
          calls << kwargs
          ["lib/sample.rb", "spec/other_spec.rb"]
        end
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
    result = build_result([])
    alpha = build_subject("Sample#alpha", source_file: "lib/sample.rb")
    beta = build_subject("Sample#beta", source_file: "lib/sample.rb")
    other = build_subject("Other#gamma", source_file: "lib/other.rb")
    calls = []

    allow(runner).to receive_messages(
      source_files: ["lib/sample.rb"],
      subject_resolver:,
      mutant_generator:,
      static_filter:,
      execution_engine:,
      integration:,
      progress_reporter: nil
    )
    allow(subject_resolver).to receive_messages(
      resolve_from_files: [alpha, beta, other],
      apply_pattern: [alpha, beta]
    )
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
# rubocop:enable RSpec/ExampleLength
