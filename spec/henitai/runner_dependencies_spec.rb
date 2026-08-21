# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::RunnerDependencies do
  def build_config(**overrides)
    defaults = {
      integration: "rspec", operators: :light, reports_dir: "reports",
      reporters: ["terminal"], checkpoint_enabled: false, checkpoint_every: 200,
      checkpoint_interval: 30.0, thresholds: { high: 80, low: 60 }
    }
    Struct.new(*defaults.keys, keyword_init: true).new(**defaults, **overrides)
  end

  def build_deps(**overrides) = described_class.new(config: build_config(**overrides))

  describe "memoized collaborators" do
    # Memoization is a correctness requirement for the coverage map and the
    # history store, not an optimisation: the incremental filter proves
    # survivor reuse against the same live map the history store records its
    # intersection set from. Two instances would be two snapshots.
    {
      subject_resolver: Henitai::SubjectResolver,
      git_diff_analyzer: Henitai::GitDiffAnalyzer,
      mutant_generator: Henitai::MutantGenerator,
      static_filter: Henitai::StaticFilter,
      execution_engine: Henitai::ExecutionEngine,
      coverage_bootstrapper: Henitai::CoverageBootstrapper,
      per_test_coverage: Henitai::PerTestCoverage
    }.each do |name, klass|
      it "builds a #{klass} for ##{name} and returns the same instance twice", :aggregate_failures do
        deps = build_deps
        built = deps.public_send(name)

        expect(built).to be_a(klass)
        expect(deps.public_send(name)).to be(built)
      end
    end

    it "returns the same history store twice" do
      deps = build_deps
      store = deps.history_store

      expect(deps.history_store).to be(store)
    end
  end

  describe "#integration" do
    it "resolves the adapter named in the configuration" do
      expect(build_deps(integration: "rspec").integration).to be_a(Henitai::Integration::Rspec)
    end

    it "returns the same adapter instance twice" do
      deps = build_deps
      adapter = deps.integration

      expect(deps.integration).to be(adapter)
    end

    it "raises for an unknown integration name" do
      expect { build_deps(integration: "nope").integration }.to raise_error(ArgumentError, /Unknown integration/)
    end
  end

  describe "#operators" do
    it "resolves the operator set named in the configuration" do
      expect(build_deps(operators: :light).operators).to all(be_a(Henitai::Operator))
    end

    it "resolves a larger set for :full than for :light" do
      expect(build_deps(operators: :full).operators.size).to be > build_deps(operators: :light).operators.size
    end
  end

  describe "#progress_reporter" do
    def checkpoint_config(reporters:)
      build_config(reporters: reporters, checkpoint_enabled: true)
    end

    it "returns a terminal reporter when reporters contains symbols" do
      deps = build_deps(reporters: [:terminal])

      expect(deps.progress_reporter(full_run: true)).to be_a(Henitai::Reporter::Terminal)
    end

    it "fans out to a composite when terminal and a file report are both enabled" do
      deps = described_class.new(config: checkpoint_config(reporters: %w[terminal json]))

      expect(deps.progress_reporter(full_run: true)).to be_a(Henitai::CompositeProgressReporter)
    end

    it "returns a lone checkpoint reporter when only a file report is enabled" do
      deps = described_class.new(config: checkpoint_config(reporters: %w[json]))

      expect(deps.progress_reporter(full_run: true)).to be_a(Henitai::CheckpointReporter)
    end

    it "skips the checkpoint reporter when checkpointing is disabled" do
      deps = build_deps(reporters: %w[json], checkpoint_enabled: false)

      expect(deps.progress_reporter(full_run: true)).to be_nil
    end

    # full_run? is a property of the invocation, not of the dependency set, so
    # this must not be memoized behind the first answer.
    it "passes full_run through on every call rather than caching the first" do
      deps = described_class.new(config: checkpoint_config(reporters: %w[json]))
      # A truthy return matters: with a nil-returning stub an `||=` memoization
      # would re-evaluate anyway and this example would prove nothing.
      allow(Henitai::CompositeProgressReporter).to receive(:for).and_return(:a_reporter)

      deps.progress_reporter(full_run: true)
      deps.progress_reporter(full_run: false)

      expect(Henitai::CompositeProgressReporter).to have_received(:for).with(hash_including(full_run: false))
    end
  end

  describe "#source_provider" do
    it "returns a lambda that reads a file's content" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "test.txt")
        File.write(path, "hello world")

        expect(build_deps.source_provider.call(path)).to eq("hello world")
      end
    end

    it "caches content per path, so a mid-run rewrite is not picked up" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "test.txt")
        File.write(path, "hello world")
        provider = build_deps.source_provider
        provider.call(path)
        File.write(path, "changed")

        expect(provider.call(path)).to eq("hello world")
      end
    end

    # A report renders without the snippet rather than aborting the run.
    it "answers an empty string for an unreadable file" do
      expect(build_deps.source_provider.call("nonexistent.txt")).to eq("")
    end

    # The cache is scoped to one reporter's lifetime, not shared process-wide.
    it "gives each call its own cache" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "test.txt")
        File.write(path, "first")
        deps = build_deps
        deps.source_provider.call(path)
        File.write(path, "second")

        expect(deps.source_provider.call(path)).to eq("second")
      end
    end
  end
end
