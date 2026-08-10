# frozen_string_literal: true

require "date"
require "fileutils"
require "json"
require "sqlite3"
require "time"
require_relative "mutant_identity"
require_relative "mutant_history_store/sql"
require_relative "mutant_history_store/subject_scans"
require_relative "mutant_history_store/verdict_cache"

module Henitai
  # Persists mutant outcomes across runs in a lightweight SQLite database.
  class MutantHistoryStore
    include SubjectScans
    include VerdictCache

    # @param per_test_coverage [PerTestCoverage, nil] live per-test coverage
    #   view used to record the full-map intersection set for survived
    #   verdicts; without it survived rows stay NULL (never reusable).
    def initialize(path:, per_test_coverage: nil)
      @path = path
      @per_test_coverage = per_test_coverage
    end

    attr_reader :path

    # Timestamps are normalized to UTC on the way in: they are stored as
    # ISO8601 strings and compared lexicographically (retirement compares a
    # mutant's last_seen_at against its subject's scan), and callers pass
    # local-zone times — `Runner#run` hands over `Time.now`. Mixing offsets
    # makes "2026-01-01T13:00:00Z" < "2026-01-01T14:00:00+02:00" as strings
    # while the opposite is true as instants. `getutc`, not `utc`, so the
    # caller's Time object is not mutated.
    # @param operators [Symbol, nil] the operator set this run generated from;
    #   stored per mutant so a later scan only retires mutants recorded under
    #   the same set.
    # @param full_scan [Boolean] whether this run regenerated each touched
    #   subject's mutants in full. False for sampled runs, which produce a
    #   fraction of the set and must not advance the retirement baseline.
    def record(result, version:, recorded_at: Time.now, operators: nil, full_scan: false)
      recorded_at = recorded_at.getutc
      FileUtils.mkdir_p(File.dirname(path))

      with_database do |db|
        ensure_schema(db)
        db.transaction do
          unless partial_rerun?(result)
            insert_run(db, result, version, recorded_at)
            record_subject_scans(db, result, recorded_at, operators) if full_scan && operators
          end
          Array(result.mutants).each do |mutant|
            upsert_mutant(db, mutant, version, recorded_at, operators)
          end
        end
      end
    end

    # Verdict-cache lookup for `--incremental`: returns the stored hashes for
    # the mutant's LATEST verdict when it is Killed or Survived — the upsert
    # keeps exactly one row per stable id, so current_status is always the
    # most recent outcome. nil for every other status, unknown ids and legacy
    # rows without hashes (recorded before the cache columns existed).
    def verdict_for(stable_id)
      return nil unless File.exist?(path)

      with_database do |db|
        ensure_schema(db)
        verdict_from_row(db.get_first_row(Sql::VERDICT_LOOKUP, stable_id))
      end
    end

    # Killed-only view of {#verdict_for}, kept for the original killed reuse
    # path.
    def killed_verdict_for(stable_id)
      verdict = verdict_for(stable_id)
      verdict if verdict && verdict[:status] == :killed
    end

    def trend_report
      with_database do |db|
        ensure_schema(db)
        {
          generatedAt: Time.now.utc.iso8601,
          runs: load_runs(db),
          mutants: load_mutants(db)
        }
      end
    end

    private

    attr_reader :per_test_coverage

    def verdict_from_row(row)
      return nil unless row && VerdictCache::CACHEABLE_STATUSES.include?(row["current_status"])
      return nil if row["subject_source_hash"].nil? || row["covered_tests_fingerprint"].nil?

      {
        status: row["current_status"].to_sym,
        subject_source_hash: row["subject_source_hash"],
        covered_tests_fingerprint: row["covered_tests_fingerprint"]
      }
    end

    def partial_rerun?(result)
      result.respond_to?(:partial_rerun?) && result.partial_rerun?
    end

    def with_database
      db = SQLite3::Database.new(path)
      db.results_as_hash = true
      yield db
    ensure
      db&.close
    end

    def ensure_schema(db)
      db.execute_batch(Sql::RUNS_TABLE)
      db.execute_batch(Sql::MUTANTS_TABLE)
      migrate_subject_scans_table(db)
      db.execute_batch(SubjectScans::SUBJECT_SCANS_TABLE)
      migrate_mutants_table(db)
    end

    # Additive, idempotent in-place migration: databases created before the
    # verdict-cache columns existed gain them on first contact, with existing
    # rows left intact (NULL hashes — valid but never reusable).
    def migrate_mutants_table(db)
      existing = db.execute("PRAGMA table_info(mutants)").map { |row| row["name"] }
      Sql::MIGRATION_COLUMNS.each do |column, type|
        next if existing.include?(column)

        db.execute("ALTER TABLE mutants ADD COLUMN #{column} #{type}")
      end
    end

    def insert_run(db, result, version, recorded_at)
      db.execute(Sql::INSERT_RUN, insert_run_bindings(result, version, recorded_at))
    end

    def upsert_mutant(db, mutant, version, recorded_at, operators)
      db.execute(
        Sql::UPSERT_MUTANT,
        upsert_mutant_bindings(mutant_history_data(db, mutant, version, recorded_at), operators)
      )
    end

    def count_mutants(mutants)
      mutants.each_with_object(Hash.new(0)) do |mutant, counts|
        counts[:total] += 1
        counts[mutant.status] += 1
      end
    end

    def stable_mutant_id(mutant)
      MutantIdentity.stable_id(mutant)
    end

    def mutation_history_entry(mutant, version, recorded_at)
      {
        version: version,
        status: mutant.status.to_s,
        recordedAt: recorded_at.iso8601
      }
    end

    def mutant_history_data(db, mutant, version, recorded_at)
      mutant_id = stable_mutant_id(mutant)
      existing = existing_mutant_row(db, mutant_id)
      history = existing_status_history(existing) << mutation_history_entry(mutant, version, recorded_at)
      first_seen = first_seen_metadata(existing, version, recorded_at)

      {
        mutant_id:, version:, recorded_at:, mutant:, history:, existing_row: existing,
        first_seen_version: first_seen[:version], first_seen_at: first_seen[:at],
        days_alive: days_alive_since(first_seen[:at], recorded_at)
      }
    end

    def existing_mutant_row(db, mutant_id)
      db.get_first_row(
        "SELECT * FROM mutants WHERE mutant_id = ?",
        mutant_id
      )
    end

    def existing_status_history(existing)
      return [] unless existing

      JSON.parse(existing["status_history"], symbolize_names: true)
    end

    def first_seen_metadata(existing, version, recorded_at)
      {
        version: existing ? existing["first_seen_version"] : version,
        at: existing ? existing["first_seen_at"] : recorded_at.iso8601
      }
    end

    def days_alive_since(first_seen_at, recorded_at)
      first_seen = Time.iso8601(first_seen_at)
      [(recorded_at.to_date - first_seen.to_date).to_i, 0].max
    end

    def load_runs(db)
      db.execute("SELECT * FROM runs ORDER BY recorded_at").map do |row|
        {
          version: row["version"],
          recordedAt: row["recorded_at"],
          mutationScore: row["mutation_score"],
          mutationScoreIndicator: row["mutation_score_indicator"],
          equivalenceUncertainty: row["equivalence_uncertainty"],
          totalMutants: row["total_mutants"],
          killedMutants: row["killed_mutants"],
          survivedMutants: row["survived_mutants"],
          timeoutMutants: row["timeout_mutants"],
          equivalentMutants: row["equivalent_mutants"]
        }
      end
    end

    def load_mutants(db)
      db.execute(SubjectScans::LOAD_MUTANTS).map do |row|
        {
          mutantId: row["mutant_id"],
          firstSeenVersion: row["first_seen_version"],
          firstSeenAt: row["first_seen_at"],
          lastSeenVersion: row["last_seen_version"],
          lastSeenAt: row["last_seen_at"],
          currentStatus: row["current_status"],
          daysAlive: row["days_alive"],
          statusHistory: JSON.parse(row["status_history"], symbolize_names: true)
        }
      end
    end

    def insert_run_bindings(result, version, recorded_at)
      summary = result.scoring_summary
      counts = count_mutants(Array(result.mutants))
      [
        version,
        recorded_at.iso8601,
        summary[:mutation_score],
        summary[:mutation_score_indicator],
        summary[:equivalence_uncertainty],
        counts[:total],
        counts[:killed],
        counts[:survived],
        counts[:timeout],
        counts[:equivalent]
      ]
    end

    def upsert_mutant_bindings(data, operators)
      mutant = data.fetch(:mutant)
      [
        data.fetch(:mutant_id),
        data.fetch(:first_seen_version),
        data.fetch(:first_seen_at),
        data.fetch(:version),
        data.fetch(:recorded_at).iso8601,
        mutant.status.to_s,
        JSON.generate(data.fetch(:history)),
        data.fetch(:days_alive),
        *verdict_cache_bindings(mutant, data[:existing_row]),
        mutant_subject_expression(mutant),
        operators&.to_s
      ]
    end
  end
end
