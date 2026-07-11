# frozen_string_literal: true

require "digest"
require "json"
require "spec_helper"
require "sqlite3"
require "tmpdir"
require "parser/current"

RSpec.describe Henitai::MutantHistoryStore do
  def build_subject
    Henitai::Subject.new(namespace: "Sample", method_name: "value")
  end

  def build_location
    {
      file: "lib/sample.rb",
      start_line: 2,
      end_line: 2,
      start_col: 0,
      end_col: 5
    }
  end

  # rubocop:disable Metrics/MethodLength
  def build_mutant(status:, mutated_source: "1 + 0")
    Struct.new(
      :subject,
      :operator,
      :description,
      :location,
      :status,
      :mutated_node
    ) do
      def killed?
        status == :killed
      end

      def survived?
        status == :survived
      end

      def equivalent?
        status == :equivalent
      end
    end.new(
      build_subject,
      "ArithmeticOperator",
      "replaced + with -",
      build_location,
      status,
      Parser::CurrentRuby.parse(mutated_source)
    )
  end
  # rubocop:enable Metrics/MethodLength

  def build_result(mutants, summary)
    Struct.new(:mutants, :scoring_summary) do
      def partial_rerun? = false
    end.new(mutants, summary)
  end

  def record_run(store, mutant:, summary:, version:, recorded_at:)
    store.record(
      build_result([mutant], summary),
      version:,
      recorded_at:
    )
  end

  def record_history_chain(store, mutant)
    record_first_history_run(store, mutant)
    mutant.status = :killed
    record_second_history_run(store, mutant)
  end

  def expect_mutant_history(mutant_report)
    expect(mutant_history_values(mutant_report)).to eq(expected_mutant_history_values)
  end

  def record_first_history_run(store, mutant)
    record_run(
      store,
      mutant:,
      summary: {
        mutation_score: 80.0,
        mutation_score_indicator: 40.0,
        equivalence_uncertainty: "~10-15% of live mutants"
      },
      version: "1.0.0",
      recorded_at: Time.utc(2026, 1, 1, 12, 0, 0)
    )
  end

  def record_second_history_run(store, mutant)
    record_run(
      store,
      mutant:,
      summary: {
        mutation_score: 90.0,
        mutation_score_indicator: 45.0,
        equivalence_uncertainty: nil
      },
      version: "1.1.0",
      recorded_at: Time.utc(2026, 1, 2, 12, 0, 0)
    )
  end

  def mutant_history_values(mutant_report)
    [
      mutant_report[:currentStatus],
      mutant_report[:daysAlive],
      mutant_report[:firstSeenVersion],
      mutant_report[:firstSeenAt],
      mutant_report[:lastSeenVersion],
      mutant_report[:lastSeenAt],
      mutant_report[:statusHistory].map { |entry| entry[:status] }
    ]
  end

  def expected_mutant_history_values
    [
      "killed",
      1,
      "1.0.0",
      "2026-01-01T12:00:00Z",
      "1.1.0",
      "2026-01-02T12:00:00Z",
      %w[survived killed]
    ]
  end

  it "returns an empty report before any runs are recorded" do
    Dir.mktmpdir do |dir|
      report = described_class.new(path: File.join(dir, "mutation-history.sqlite3")).trend_report

      expect(
        [
          report[:generatedAt].match?(/\A\d{4}-\d{2}-\d{2}T/),
          report[:runs],
          report[:mutants]
        ]
      ).to eq([true, [], []])
    end
  end

  it "records run summaries" do
    Dir.mktmpdir do |dir|
      store = described_class.new(path: File.join(dir, "mutation-history.sqlite3"))
      store.record(
        build_result(
          [build_mutant(status: :survived)],
          {
            mutation_score: 80.0,
            mutation_score_indicator: 40.0,
            equivalence_uncertainty: "~10-15% of live mutants"
          }
        ),
        version: "1.0.0",
        recorded_at: Time.utc(2026, 1, 1, 12, 0, 0)
      )

      expect(store.trend_report[:runs].first).to eq(
        version: "1.0.0",
        recordedAt: "2026-01-01T12:00:00Z",
        mutationScore: 80.0,
        mutationScoreIndicator: 40.0,
        equivalenceUncertainty: "~10-15% of live mutants",
        totalMutants: 1,
        killedMutants: 0,
        survivedMutants: 1,
        timeoutMutants: 0,
        equivalentMutants: 0
      )
    end
  end

  it "generates a 64-character hexadecimal mutant ID" do
    Dir.mktmpdir do |dir|
      store = described_class.new(path: File.join(dir, "mutation-history.sqlite3"))
      store.record(
        build_result(
          [build_mutant(status: :survived)],
          { mutation_score: 80.0, mutation_score_indicator: 40.0, equivalence_uncertainty: nil }
        ),
        version: "1.0.0",
        recorded_at: Time.utc(2026, 1, 1)
      )

      expect(store.trend_report[:mutants].first[:mutantId]).to match(/\A[0-9a-f]{64}\z/)
    end
  end

  it "uses a stable SHA-256 mutant ID" do
    Dir.mktmpdir do |dir|
      store = described_class.new(path: File.join(dir, "mutation-history.sqlite3"))
      mutant = build_mutant(status: :survived, mutated_source: "1 - 0")

      store.record(
        build_result(
          [mutant],
          { mutation_score: 80.0, mutation_score_indicator: 40.0, equivalence_uncertainty: nil }
        ),
        version: "1.0.0",
        recorded_at: Time.utc(2026, 1, 1)
      )

      expect(store.trend_report[:mutants].first[:mutantId]).to eq(Henitai::MutantIdentity.stable_id(mutant))
    end
  end

  it "returns status history entries with symbol keys" do
    Dir.mktmpdir do |dir|
      store = described_class.new(path: File.join(dir, "mutation-history.sqlite3"))
      store.record(
        build_result(
          [build_mutant(status: :survived)],
          { mutation_score: 80.0, mutation_score_indicator: 40.0, equivalence_uncertainty: nil }
        ),
        version: "1.0.0",
        recorded_at: Time.utc(2026, 1, 1)
      )

      entry = store.trend_report[:mutants].first[:statusHistory].first
      aggregate_failures do
        expect(entry).to have_key(:status)
        expect(entry).not_to have_key("status")
      end
    end
  end

  it "appends mutant history across repeated runs" do
    Dir.mktmpdir do |dir|
      store = described_class.new(path: File.join(dir, "mutation-history.sqlite3"))
      mutant = build_mutant(status: :survived)

      record_history_chain(store, mutant)
      expect_mutant_history(store.trend_report[:mutants].first)
    end
  end

  describe "partial rerun result" do
    def partial_result(mutants)
      result = build_result(
        mutants,
        { mutation_score: 80.0, mutation_score_indicator: 40.0, equivalence_uncertainty: nil }
      )
      allow(result).to receive(:partial_rerun?).and_return(true)
      result
    end

    it "does not insert a runs row for a partial rerun" do
      Dir.mktmpdir do |dir|
        store = described_class.new(path: File.join(dir, "mutation-history.sqlite3"))
        store.record(partial_result([build_mutant(status: :survived)]), version: "0.1.0")

        db = SQLite3::Database.new(File.join(dir, "mutation-history.sqlite3"))
        db.results_as_hash = true
        count = db.get_first_value("SELECT COUNT(*) FROM runs")
        db.close

        expect(count).to eq(0)
      end
    end

    it "still upserts mutant rows for a partial rerun" do
      Dir.mktmpdir do |dir|
        store = described_class.new(path: File.join(dir, "mutation-history.sqlite3"))
        mutants = [build_mutant(status: :survived)]
        store.record(partial_result(mutants), version: "0.1.0")

        db = SQLite3::Database.new(File.join(dir, "mutation-history.sqlite3"))
        db.results_as_hash = true
        count = db.get_first_value("SELECT COUNT(*) FROM mutants")
        db.close

        expect(count).to eq(1)
      end
    end
  end

  describe "verdict cache" do
    def build_cacheable_mutant(dir, status:)
      source = File.join(dir, "sample.rb")
      File.write(source, "class Sample\n  def value = 1\nend\n")
      test = File.join(dir, "sample_spec.rb")
      File.write(test, "it works\n")

      mutant = build_mutant(status:)
      mutant.subject.instance_variable_set(:@source_file, source)
      mutant.subject.instance_variable_set(:@source_range, 2..2)
      mutant.define_singleton_method(:covered_by) { [test] }
      mutant
    end

    def store_at(dir, per_test_coverage: nil)
      described_class.new(path: File.join(dir, "mutation-history.sqlite3"), per_test_coverage:)
    end

    def summary
      { mutation_score: 100.0, mutation_score_indicator: 100.0, equivalence_uncertainty: nil }
    end

    def coverage_double(covering_tests)
      coverage = instance_double(Henitai::PerTestCoverage)
      allow(coverage).to receive(:tests_covering).and_return(covering_tests)
      coverage
    end

    it "returns the stored hashes for a killed mutant" do
      Dir.mktmpdir do |dir|
        store = store_at(dir)
        mutant = build_cacheable_mutant(dir, status: :killed)
        store.record(build_result([mutant], summary), version: "0.1.0")

        verdict = store.killed_verdict_for(Henitai::MutantIdentity.stable_id(mutant))

        expect(
          status: verdict[:status],
          subject_hash: verdict[:subject_source_hash],
          fingerprint_current: Henitai::VerdictFingerprint.tests_fingerprint_current?(
            verdict[:covered_tests_fingerprint]
          )
        ).to eq(
          status: :killed,
          subject_hash: Henitai::VerdictFingerprint.subject_source_hash(mutant),
          fingerprint_current: true
        )
      end
    end

    it "preserves stored fingerprints when re-recording a cache-hit mutant" do
      Dir.mktmpdir do |dir|
        store = store_at(dir)
        mutant = build_cacheable_mutant(dir, status: :killed)
        store.record(build_result([mutant], summary), version: "0.1.0")

        cached = build_cacheable_mutant(dir, status: :killed)
        cached.define_singleton_method(:covered_by) { nil }
        cached.define_singleton_method(:from_cache?) { true }
        store.record(build_result([cached], summary), version: "0.1.1")

        expect(store.killed_verdict_for(Henitai::MutantIdentity.stable_id(mutant))).not_to be_nil
      end
    end

    it "does not cache a cache-hit mutant without stored fingerprints" do
      Dir.mktmpdir do |dir|
        store = store_at(dir)
        mutant = build_cacheable_mutant(dir, status: :killed)
        mutant.define_singleton_method(:covered_by) { nil }
        mutant.define_singleton_method(:from_cache?) { true }

        store.record(build_result([mutant], summary), version: "0.1.0")

        expect(store.killed_verdict_for(Henitai::MutantIdentity.stable_id(mutant))).to be_nil
      end
    end

    it "returns nil for survived mutants" do
      Dir.mktmpdir do |dir|
        store = store_at(dir)
        mutant = build_cacheable_mutant(dir, status: :survived)
        store.record(build_result([mutant], summary), version: "0.1.0")

        expect(store.killed_verdict_for(Henitai::MutantIdentity.stable_id(mutant))).to be_nil
      end
    end

    describe "survived verdicts" do
      it "persists the full-map intersection set for survived mutants, not covered_by" do
        Dir.mktmpdir do |dir|
          mutant = build_cacheable_mutant(dir, status: :survived)
          covering_test = File.join(dir, "sample_spec.rb")
          mutant.define_singleton_method(:covered_by) { ["not/the/intersection_spec.rb"] }
          store = store_at(dir, per_test_coverage: coverage_double([covering_test]))

          store.record(build_result([mutant], summary), version: "0.1.0")
          verdict = store.verdict_for(Henitai::MutantIdentity.stable_id(mutant))

          expect(
            status: verdict[:status],
            subject_hash: verdict[:subject_source_hash],
            recorded_paths: JSON.parse(verdict[:covered_tests_fingerprint]).fetch("paths"),
            dependencies_present: !JSON.parse(verdict[:covered_tests_fingerprint])["dependencies"].nil?
          ).to eq(
            status: :survived,
            subject_hash: Henitai::VerdictFingerprint.subject_source_hash(mutant),
            recorded_paths: [covering_test],
            dependencies_present: true
          )
        end
      end

      it "records no survived fingerprint when the live intersection set is empty" do
        Dir.mktmpdir do |dir|
          mutant = build_cacheable_mutant(dir, status: :survived)
          store = store_at(dir, per_test_coverage: coverage_double([]))

          store.record(build_result([mutant], summary), version: "0.1.0")

          expect(store.verdict_for(Henitai::MutantIdentity.stable_id(mutant))).to be_nil
        end
      end

      it "records no survived fingerprint without a per-test coverage collaborator" do
        Dir.mktmpdir do |dir|
          mutant = build_cacheable_mutant(dir, status: :survived)
          store = store_at(dir)

          store.record(build_result([mutant], summary), version: "0.1.0")

          expect(store.verdict_for(Henitai::MutantIdentity.stable_id(mutant))).to be_nil
        end
      end

      it "keeps stored fingerprints when a survived fingerprint cannot be recomputed" do
        Dir.mktmpdir do |dir|
          mutant = build_cacheable_mutant(dir, status: :survived)
          covering_test = File.join(dir, "sample_spec.rb")
          store = store_at(dir, per_test_coverage: coverage_double([covering_test]))
          store.record(build_result([mutant], summary), version: "0.1.0")
          stored = store.verdict_for(Henitai::MutantIdentity.stable_id(mutant))

          restored = build_cacheable_mutant(dir, status: :survived)
          restored.define_singleton_method(:covered_by) { ["restored_by_survivors_from_spec.rb"] }
          degraded = store_at(dir, per_test_coverage: coverage_double([]))
          degraded.record(build_result([restored], summary), version: "0.1.1")

          expect(degraded.verdict_for(Henitai::MutantIdentity.stable_id(mutant))).to eq(stored)
        end
      end

      it "carries stored fingerprints forward for cache-hit survivors" do
        Dir.mktmpdir do |dir|
          mutant = build_cacheable_mutant(dir, status: :survived)
          covering_test = File.join(dir, "sample_spec.rb")
          store = store_at(dir, per_test_coverage: coverage_double([covering_test]))
          store.record(build_result([mutant], summary), version: "0.1.0")
          stored = store.verdict_for(Henitai::MutantIdentity.stable_id(mutant))

          cached = build_cacheable_mutant(dir, status: :survived)
          cached.define_singleton_method(:covered_by) { nil }
          cached.define_singleton_method(:from_cache?) { true }
          bare = store_at(dir)
          bare.record(build_result([cached], summary), version: "0.1.1")

          expect(bare.verdict_for(Henitai::MutantIdentity.stable_id(mutant))).to eq(stored)
        end
      end
    end

    describe "#verdict_for" do
      it "resolves the latest verdict when a killed mutant later survives" do
        Dir.mktmpdir do |dir|
          covering_test = File.join(dir, "sample_spec.rb")
          store = store_at(dir, per_test_coverage: coverage_double([covering_test]))
          killed = build_cacheable_mutant(dir, status: :killed)
          store.record(build_result([killed], summary), version: "0.1.0")

          survived = build_cacheable_mutant(dir, status: :survived)
          store.record(build_result([survived], summary), version: "0.1.1")

          expect(
            store.verdict_for(Henitai::MutantIdentity.stable_id(killed))[:status]
          ).to eq(:survived)
        end
      end

      it "resolves the latest verdict when a survived mutant later gets killed" do
        Dir.mktmpdir do |dir|
          covering_test = File.join(dir, "sample_spec.rb")
          store = store_at(dir, per_test_coverage: coverage_double([covering_test]))
          survived = build_cacheable_mutant(dir, status: :survived)
          store.record(build_result([survived], summary), version: "0.1.0")

          killed = build_cacheable_mutant(dir, status: :killed)
          store.record(build_result([killed], summary), version: "0.1.1")

          expect(
            store.verdict_for(Henitai::MutantIdentity.stable_id(survived))[:status]
          ).to eq(:killed)
        end
      end

      it "returns nil for statuses that are never reusable" do
        Dir.mktmpdir do |dir|
          store = store_at(dir, per_test_coverage: coverage_double([File.join(dir, "sample_spec.rb")]))
          mutant = build_cacheable_mutant(dir, status: :timeout)
          store.record(build_result([mutant], summary), version: "0.1.0")

          expect(store.verdict_for(Henitai::MutantIdentity.stable_id(mutant))).to be_nil
        end
      end

      it "returns nil for unknown ids and missing databases" do
        Dir.mktmpdir do |dir|
          missing = store_at(dir).verdict_for("anything")
          store = store_at(dir)
          store.record(build_result([build_cacheable_mutant(dir, status: :killed)], summary), version: "0.1.0")

          expect([missing, store.verdict_for("nope")]).to eq([nil, nil])
        end
      end
    end

    it "returns nil for unknown ids" do
      Dir.mktmpdir do |dir|
        store = store_at(dir)
        store.record(build_result([build_cacheable_mutant(dir, status: :killed)], summary), version: "0.1.0")

        expect(store.killed_verdict_for("nope")).to be_nil
      end
    end

    it "returns nil when the database does not exist yet" do
      Dir.mktmpdir do |dir|
        expect(store_at(dir).killed_verdict_for("anything")).to be_nil
      end
    end

    it "does not create a database during a lookup" do
      Dir.mktmpdir do |dir|
        store = store_at(dir)

        store.killed_verdict_for("anything")

        expect(File).not_to exist(store.path)
      end
    end

    describe "legacy database migration" do
      def legacy_mutants_table
        <<~SQL
          CREATE TABLE mutants (
            mutant_id TEXT PRIMARY KEY,
            first_seen_version TEXT NOT NULL,
            first_seen_at TEXT NOT NULL,
            last_seen_version TEXT NOT NULL,
            last_seen_at TEXT NOT NULL,
            current_status TEXT NOT NULL,
            status_history TEXT NOT NULL,
            days_alive INTEGER NOT NULL
          );
        SQL
      end

      def create_legacy_database(dir)
        path = File.join(dir, "mutation-history.sqlite3")
        db = SQLite3::Database.new(path)
        db.execute_batch(legacy_mutants_table)
        db.execute(
          "INSERT INTO mutants VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
          ["legacy-id", "0.0.9", "2026-01-01T00:00:00Z", "0.0.9", "2026-01-01T00:00:00Z",
           "killed", "[]", 0]
        )
        db.close
        path
      end

      it "migrates in place and keeps legacy rows intact but non-reusable" do
        Dir.mktmpdir do |dir|
          path = create_legacy_database(dir)
          store = described_class.new(path:)

          verdict = store.killed_verdict_for("legacy-id")

          db = SQLite3::Database.new(path)
          db.results_as_hash = true
          row = db.get_first_row("SELECT * FROM mutants WHERE mutant_id = 'legacy-id'")
          db.close

          expect(
            verdict: verdict,
            status: row["current_status"],
            columns_added: row.key?("subject_source_hash") && row.key?("covered_tests_fingerprint")
          ).to eq(verdict: nil, status: "killed", columns_added: true)
        end
      end

      it "accepts new records after migrating a legacy database" do
        Dir.mktmpdir do |dir|
          path = create_legacy_database(dir)
          store = described_class.new(path:)
          mutant = build_cacheable_mutant(dir, status: :killed)

          store.record(build_result([mutant], summary), version: "0.1.0")

          expect(store.killed_verdict_for(Henitai::MutantIdentity.stable_id(mutant))).not_to be_nil
        end
      end
    end
  end
end
