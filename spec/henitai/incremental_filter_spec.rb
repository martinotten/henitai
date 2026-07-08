# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::IncrementalFilter do
  def build_mutant(stable_id:, source_file:, source_range: 2..2, status: :pending)
    subject = Struct.new(:source_file, :source_range).new(source_file, source_range)
    Struct.new(:subject, :stable_id, :status, :from_cache) do
      def pending? = status == :pending
    end.new(subject, stable_id, status, false)
  end

  def build_store(verdicts)
    store = instance_double(Henitai::MutantHistoryStore)
    allow(store).to receive(:killed_verdict_for) { |stable_id| verdicts[stable_id] }
    store
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

  it "leaves non-pending mutants untouched without consulting the store" do
    Dir.mktmpdir do |dir|
      source, = write_workspace(dir)
      mutant = build_mutant(stable_id: "abc", source_file: source, status: :ignored)
      store = instance_double(Henitai::MutantHistoryStore)

      described_class.new(history_store: store).apply([mutant])

      expect(mutant.status).to eq(:ignored)
    end
  end
end
