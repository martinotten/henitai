# frozen_string_literal: true

require "date"
require "fileutils"
require "json"
require "sqlite3"
require "time"
require_relative "mutant_identity"
require_relative "mutant_history_store/sql"

module Henitai
  # Persists mutant outcomes across runs in a lightweight SQLite database.
  class MutantHistoryStore
    def initialize(path:)
      @path = path
    end

    attr_reader :path

    def record(result, version:, recorded_at: Time.now.utc)
      FileUtils.mkdir_p(File.dirname(path))

      with_database do |db|
        ensure_schema(db)
        db.transaction do
          insert_run(db, result, version, recorded_at) unless partial_rerun?(result)
          Array(result.mutants).each do |mutant|
            upsert_mutant(db, mutant, version, recorded_at)
          end
        end
      end
    end

    # Verdict-cache lookup for `--incremental`: returns the stored hashes for
    # a Killed row, or nil for survivors, unknown ids and legacy rows without
    # hashes (recorded before the cache columns existed).
    def killed_verdict_for(stable_id)
      return nil unless File.exist?(path)

      with_database do |db|
        ensure_schema(db)
        row = db.get_first_row(Sql::KILLED_VERDICT, stable_id)
        next nil unless row && row["current_status"] == "killed"
        next nil if row["subject_source_hash"].nil? || row["covered_tests_fingerprint"].nil?

        {
          status: :killed,
          subject_source_hash: row["subject_source_hash"],
          covered_tests_fingerprint: row["covered_tests_fingerprint"]
        }
      end
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

    def upsert_mutant(db, mutant, version, recorded_at)
      db.execute(
        Sql::UPSERT_MUTANT,
        upsert_mutant_bindings(mutant_history_data(db, mutant, version, recorded_at))
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
      history = existing_status_history(existing)
      history << mutation_history_entry(mutant, version, recorded_at)
      first_seen = first_seen_metadata(existing, version, recorded_at)

      {
        mutant_id: mutant_id,
        first_seen_version: first_seen[:version],
        first_seen_at: first_seen[:at],
        version: version,
        recorded_at: recorded_at,
        mutant: mutant,
        history: history,
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
      db.execute("SELECT * FROM mutants ORDER BY first_seen_at, mutant_id").map do |row|
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

    def upsert_mutant_bindings(data)
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
        *verdict_cache_bindings(mutant)
      ]
    end

    # Hashes are persisted for killed mutants only — they are the reusable
    # verdicts; every other status stays NULL and always re-executes.
    def verdict_cache_bindings(mutant)
      return [nil, nil] unless mutant.status.to_s == "killed"

      [
        VerdictFingerprint.subject_source_hash(mutant),
        VerdictFingerprint.tests_fingerprint(covered_tests_for(mutant))
      ]
    end

    def covered_tests_for(mutant)
      mutant.respond_to?(:covered_by) ? mutant.covered_by : nil
    end
  end
end
