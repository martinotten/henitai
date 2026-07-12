# frozen_string_literal: true

require "parser/current"
require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::IncrementalFilter do
  def build_mutant(stable_id:, source_file:, source_range: 2..2, status: :pending)
    subject = Struct.new(:source_file, :source_range).new(source_file, source_range)
    location = { file: source_file, start_line: 2, end_line: 2 }
    Struct.new(:subject, :stable_id, :status, :from_cache, :location) do
      def pending? = status == :pending
    end.new(subject, stable_id, status, false, location)
  end

  def build_store(verdicts)
    store = instance_double(Henitai::MutantHistoryStore)
    allow(store).to receive(:verdict_for) { |stable_id| verdicts[stable_id] }
    store
  end

  def build_coverage(covering_tests, available: true)
    coverage = instance_double(Henitai::PerTestCoverage)
    allow(coverage).to receive_messages(available?: available, tests_covering: covering_tests)
    coverage
  end

  def write_workspace(dir)
    source = File.join(dir, "sample.rb")
    File.write(source, "class Sample\n  def value = 1\nend\n")
    test = File.join(dir, "sample_spec.rb")
    File.write(test, "it works\n")
    [source, test]
  end

  def verdict_for(mutant, test)
    {
      status: :killed,
      subject_source_hash: Henitai::VerdictFingerprint.subject_source_hash(mutant),
      covered_tests_fingerprint: Henitai::VerdictFingerprint.tests_fingerprint([test])
    }
  end

  it "marks a mutant with matching id and unchanged hashes as a cache hit" do
    Dir.mktmpdir do |dir|
      source, test = write_workspace(dir)
      mutant = build_mutant(stable_id: "abc", source_file: source)
      store = build_store("abc" => verdict_for(mutant, test))

      described_class.new(history_store: store).apply([mutant])

      expect([mutant.status, mutant.from_cache]).to eq([:killed, true])
    end
  end

  it "re-runs when the subject source changed" do
    Dir.mktmpdir do |dir|
      source, test = write_workspace(dir)
      mutant = build_mutant(stable_id: "abc", source_file: source)
      verdict = verdict_for(mutant, test)
      File.write(source, "class Sample\n  def value = 2\nend\n")
      store = build_store("abc" => verdict)

      described_class.new(history_store: store).apply([mutant])

      expect([mutant.status, mutant.from_cache]).to eq([:pending, false])
    end
  end

  it "re-runs when a covering test file changed" do
    Dir.mktmpdir do |dir|
      source, test = write_workspace(dir)
      mutant = build_mutant(stable_id: "abc", source_file: source)
      verdict = verdict_for(mutant, test)
      File.write(test, "it works differently\n")
      store = build_store("abc" => verdict)

      described_class.new(history_store: store).apply([mutant])

      expect(mutant.status).to eq(:pending)
    end
  end

  it "re-runs when a covering test file was deleted" do
    Dir.mktmpdir do |dir|
      source, test = write_workspace(dir)
      mutant = build_mutant(stable_id: "abc", source_file: source)
      verdict = verdict_for(mutant, test)
      File.delete(test)
      store = build_store("abc" => verdict)

      described_class.new(history_store: store).apply([mutant])

      expect(mutant.status).to eq(:pending)
    end
  end

  it "re-runs when the store has no reusable verdict" do
    Dir.mktmpdir do |dir|
      source, = write_workspace(dir)
      mutant = build_mutant(stable_id: "unknown", source_file: source)
      store = build_store({})

      described_class.new(history_store: store).apply([mutant])

      expect(mutant.status).to eq(:pending)
    end
  end

  it "never reuses verdicts for mutants sharing a stable id" do
    Dir.mktmpdir do |dir|
      source, test = write_workspace(dir)
      first = build_mutant(stable_id: "dup", source_file: source)
      second = build_mutant(stable_id: "dup", source_file: source)
      store = build_store("dup" => verdict_for(first, test))

      described_class.new(history_store: store).apply([first, second])

      expect([first.status, second.status]).to eq(%i[pending pending])
    end
  end

  it "reuses verdicts independently for two mutants that would have collided pre-fix" do # rubocop:disable RSpec/MultipleExpectations
    Dir.mktmpdir do |dir|
      source, test = write_workspace(dir)
      subject = Henitai::Subject.new(namespace: "Sample", method_name: "value",
                                     source_location: { file: source, range: (1..3) })
      nil_node = Parser::CurrentRuby.parse("nil")
      first = Henitai::Mutant.new(
        subject:, operator: "MethodExpression", nodes: { original: nil_node, mutated: nil_node },
        description: "replaced method call with nil",
        location: { file: source, start_line: 2, end_line: 2, start_col: 2, end_col: 10 }
      )
      second = Henitai::Mutant.new(
        subject:, operator: "MethodExpression", nodes: { original: nil_node, mutated: nil_node },
        description: "replaced method call with nil",
        location: { file: source, start_line: 2, end_line: 2, start_col: 20, end_col: 28 }
      )
      expect(first.stable_id).not_to eq(second.stable_id)

      store = build_store(first.stable_id => verdict_for(first, test),
                          second.stable_id => verdict_for(second, test))

      described_class.new(history_store: store).apply([first, second])

      expect([first.status, second.status]).to eq(%i[killed killed])
    end
  end

  it "leaves non-pending mutants untouched without consulting the store" do
    Dir.mktmpdir do |dir|
      source, = write_workspace(dir)
      mutant = build_mutant(stable_id: "abc", source_file: source, status: :ignored)
      store = instance_double(Henitai::MutantHistoryStore)

      described_class.new(history_store: store).apply([mutant])

      expect(mutant.status).to eq(:ignored)
    end
  end

  describe "survived verdict reuse" do
    def recorded_dependency_sha = "deps-sha"

    def survived_verdict_for(mutant, tests, dependency_sha: recorded_dependency_sha)
      {
        status: :survived,
        subject_source_hash: Henitai::VerdictFingerprint.subject_source_hash(mutant),
        covered_tests_fingerprint: Henitai::VerdictFingerprint.survivor_tests_fingerprint(
          tests, dependency_sha:
        )
      }
    end

    def build_filter(store, coverage, dependency_fingerprint: recorded_dependency_sha)
      described_class.new(
        history_store: store,
        per_test_coverage: coverage,
        dependency_fingerprint:
      )
    end

    it "reuses a survived verdict when source, covering set and dependencies are unchanged" do
      Dir.mktmpdir do |dir|
        source, test = write_workspace(dir)
        mutant = build_mutant(stable_id: "abc", source_file: source)
        store = build_store("abc" => survived_verdict_for(mutant, [test]))

        build_filter(store, build_coverage([test])).apply([mutant])

        expect([mutant.status, mutant.from_cache]).to eq([:survived, true])
      end
    end

    it "re-runs when a new test now covers the subject" do
      Dir.mktmpdir do |dir|
        source, test = write_workspace(dir)
        extra = File.join(dir, "extra_spec.rb")
        File.write(extra, "it kills\n")
        mutant = build_mutant(stable_id: "abc", source_file: source)
        store = build_store("abc" => survived_verdict_for(mutant, [test]))

        build_filter(store, build_coverage([extra, test])).apply([mutant])

        expect([mutant.status, mutant.from_cache]).to eq([:pending, false])
      end
    end

    it "re-runs when a covering test dropped out of the live set" do
      Dir.mktmpdir do |dir|
        source, test = write_workspace(dir)
        gone = File.join(dir, "gone_spec.rb")
        File.write(gone, "it worked\n")
        mutant = build_mutant(stable_id: "abc", source_file: source)
        store = build_store("abc" => survived_verdict_for(mutant, [test, gone]))

        build_filter(store, build_coverage([test])).apply([mutant])

        expect(mutant.status).to eq(:pending)
      end
    end

    it "re-runs when a covering test's content changed" do
      Dir.mktmpdir do |dir|
        source, test = write_workspace(dir)
        mutant = build_mutant(stable_id: "abc", source_file: source)
        store = build_store("abc" => survived_verdict_for(mutant, [test]))
        File.write(test, "it kills now\n")

        build_filter(store, build_coverage([test])).apply([mutant])

        expect(mutant.status).to eq(:pending)
      end
    end

    it "re-runs when the subject source changed" do
      Dir.mktmpdir do |dir|
        source, test = write_workspace(dir)
        mutant = build_mutant(stable_id: "abc", source_file: source)
        store = build_store("abc" => survived_verdict_for(mutant, [test]))
        File.write(source, "class Sample\n  def value = 2\nend\n")

        build_filter(store, build_coverage([test])).apply([mutant])

        expect(mutant.status).to eq(:pending)
      end
    end

    it "re-runs when the dependency fingerprint changed" do
      Dir.mktmpdir do |dir|
        source, test = write_workspace(dir)
        mutant = build_mutant(stable_id: "abc", source_file: source)
        store = build_store("abc" => survived_verdict_for(mutant, [test]))

        build_filter(store, build_coverage([test]), dependency_fingerprint: "other-sha").apply([mutant])

        expect(mutant.status).to eq(:pending)
      end
    end

    it "re-runs when the current dependency fingerprint is unavailable" do
      Dir.mktmpdir do |dir|
        source, test = write_workspace(dir)
        mutant = build_mutant(stable_id: "abc", source_file: source)
        store = build_store("abc" => survived_verdict_for(mutant, [test]))

        build_filter(store, build_coverage([test]), dependency_fingerprint: nil).apply([mutant])

        expect(mutant.status).to eq(:pending)
      end
    end

    it "re-runs when the per-test coverage map is unavailable or empty" do
      Dir.mktmpdir do |dir|
        source, test = write_workspace(dir)
        mutant = build_mutant(stable_id: "abc", source_file: source)
        store = build_store("abc" => survived_verdict_for(mutant, [test]))

        build_filter(store, build_coverage([], available: false)).apply([mutant])

        expect(mutant.status).to eq(:pending)
      end
    end

    it "re-runs when no per-test coverage collaborator is injected" do
      Dir.mktmpdir do |dir|
        source, test = write_workspace(dir)
        mutant = build_mutant(stable_id: "abc", source_file: source)
        store = build_store("abc" => survived_verdict_for(mutant, [test]))

        described_class.new(history_store: store).apply([mutant])

        expect(mutant.status).to eq(:pending)
      end
    end

    it "re-runs when the recorded set was over-selected (selector-fallback style)" do
      Dir.mktmpdir do |dir|
        source, test = write_workspace(dir)
        unrelated = File.join(dir, "unrelated_spec.rb")
        File.write(unrelated, "it does not cover\n")
        mutant = build_mutant(stable_id: "abc", source_file: source)
        store = build_store("abc" => survived_verdict_for(mutant, [test, unrelated]))

        build_filter(store, build_coverage([test])).apply([mutant])

        expect(mutant.status).to eq(:pending)
      end
    end

    it "re-runs when the live covering set is empty while the recorded set is not" do
      Dir.mktmpdir do |dir|
        source, test = write_workspace(dir)
        mutant = build_mutant(stable_id: "abc", source_file: source)
        store = build_store("abc" => survived_verdict_for(mutant, [test]))

        build_filter(store, build_coverage([])).apply([mutant])

        expect(mutant.status).to eq(:pending)
      end
    end

    it "never reuses survived verdicts for mutants sharing a stable id" do
      Dir.mktmpdir do |dir|
        source, test = write_workspace(dir)
        first = build_mutant(stable_id: "dup", source_file: source)
        second = build_mutant(stable_id: "dup", source_file: source)
        store = build_store("dup" => survived_verdict_for(first, [test]))

        build_filter(store, build_coverage([test])).apply([first, second])

        expect([first.status, second.status]).to eq(%i[pending pending])
      end
    end

    it "still reuses killed verdicts when survivor collaborators are injected" do
      Dir.mktmpdir do |dir|
        source, test = write_workspace(dir)
        mutant = build_mutant(stable_id: "abc", source_file: source)
        store = build_store("abc" => verdict_for(mutant, test))

        build_filter(store, build_coverage([test])).apply([mutant])

        expect([mutant.status, mutant.from_cache]).to eq([:killed, true])
      end
    end
  end
end
