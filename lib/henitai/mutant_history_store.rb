# frozen_string_literal: true

require "date"
require "digest"
require "fileutils"
require "json"
require "sqlite3"
require "time"
require "unparser"

module Henitai
  # Persists mutant outcomes across runs in a lightweight SQLite database.
  # rubocop:disable Metrics/ClassLength
  class MutantHistoryStore
    RUNS_TABLE_SQL = <<~SQL
      CREATE TABLE IF NOT EXISTS runs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        version TEXT NOT NULL,
        recorded_at TEXT NOT NULL,
        mutation_score REAL,
        mutation_score_indicator REAL,
        equivalence_uncertainty TEXT,
        total_mutants INTEGER NOT NULL,
        killed_mutants INTEGER NOT NULL,
        survived_mutants INTEGER NOT NULL,
        timeout_mutants INTEGER NOT NULL,
        equivalent_mutants INTEGER NOT NULL
      );
    SQL

    MUTANTS_TABLE_SQL = <<~SQL
      CREATE TABLE IF NOT EXISTS mutants (
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

    INSERT_RUN_SQL = <<~SQL
      INSERT INTO runs (
        version,
        recorded_at,
        mutation_score,
        mutation_score_indicator,
        equivalence_uncertainty,
        total_mutants,
        killed_mutants,
        survived_mutants,
        timeout_mutants,
        equivalent_mutants
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    SQL

    UPSERT_MUTANT_SQL = <<~SQL
      INSERT INTO mutants (
        mutant_id,
        first_seen_version,
        first_seen_at,
        last_seen_version,
        last_seen_at,
        current_status,
        status_history,
        days_alive
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(mutant_id) DO UPDATE SET
        last_seen_version = excluded.last_seen_version,
        last_seen_at = excluded.last_seen_at,
        current_status = excluded.current_status,
        status_history = excluded.status_history,
        days_alive = excluded.days_alive
    SQL

    def initialize(path:)
      @path = path
    end

    attr_reader :path

    def record(result, version:, recorded_at: Time.now.utc)
      FileUtils.mkdir_p(File.dirname(path))

      with_database do |db|
        ensure_schema(db)
        db.transaction
        insert_run(db, result, version, recorded_at)
        Array(result.mutants).each do |mutant|
          upsert_mutant(db, mutant, version, recorded_at)
        end
        db.commit
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

    def with_database
      db = SQLite3::Database.new(path)
      db.results_as_hash = true
      yield db
    ensure
      db&.close
    end

    def ensure_schema(db)
      db.execute_batch(RUNS_TABLE_SQL)
      db.execute_batch(MUTANTS_TABLE_SQL)
    end

    def insert_run(db, result, version, recorded_at)
      db.execute(INSERT_RUN_SQL, insert_run_bindings(result, version, recorded_at))
    end

    def upsert_mutant(db, mutant, version, recorded_at)
      db.execute(
        UPSERT_MUTANT_SQL,
        upsert_mutant_bindings(mutant_history_data(mutant, version, recorded_at))
      )
    end

    def count_mutants(mutants)
      mutants.each_with_object(Hash.new(0)) do |mutant, counts|
        counts[:total] += 1
        counts[mutant.status] += 1
      end
    end

    def stable_mutant_id(mutant)
      Digest::SHA256.hexdigest(
        [
          mutant.subject.expression,
          mutant.operator,
          mutant.description,
          mutant.location[:file],
          mutant.location[:start_line],
          mutant.location[:end_line],
          mutant.location[:start_col],
          mutant.location[:end_col],
          mutation_signature(mutant)
        ].join("\0")
      )
    end

    def mutation_signature(mutant)
      Unparser.unparse(mutant.mutated_node)
    rescue StandardError
      mutant.mutated_node.class.name
    end

    def mutation_history_entry(mutant, version, recorded_at)
      {
        version: version,
        status: mutant.status.to_s,
        recordedAt: recorded_at.iso8601
      }
    end

    def mutant_history_data(mutant, version, recorded_at)
      mutant_id = stable_mutant_id(mutant)
      existing = existing_mutant_row(mutant_id)
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

    def existing_mutant_row(mutant_id)
      with_database do |db|
        db.get_first_row(
          "SELECT * FROM mutants WHERE mutant_id = ?",
          mutant_id
        )
      end
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
      [
        data.fetch(:mutant_id),
        data.fetch(:first_seen_version),
        data.fetch(:first_seen_at),
        data.fetch(:version),
        data.fetch(:recorded_at).iso8601,
        data.fetch(:mutant).status.to_s,
        JSON.generate(data.fetch(:history)),
        data.fetch(:days_alive)
      ]
    end
  end
end
# rubocop:enable Metrics/ClassLength
