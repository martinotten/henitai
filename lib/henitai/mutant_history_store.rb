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
require_relative "mutant_history_store/database"

module Henitai
  # Persists mutant outcomes across runs in a lightweight SQLite database.
  class MutantHistoryStore
    # What every mutant row of one write shares.
    UpsertContext = Data.define(:version, :recorded_at, :run_id, :operators)

    include SubjectScans
    include VerdictCache
    include Database

    # @param per_test_coverage [PerTestCoverage, nil] live per-test coverage
    #   view used to record the full-map intersection set for survived
    #   verdicts; without it survived rows stay NULL (never reusable).
    # @param reuse_context [ReuseContext, nil] fingerprint recorded with every
    #   cached verdict; without it no verdict is cached (never reusable).
    # @param provenance [ExecutionProvenance, nil] fingerprints are written
    #   only for verdicts whose inputs it reports intact (ADR-19); nil skips
    #   the check.
    def initialize(path:, per_test_coverage: nil, reuse_context: nil, provenance: nil)
      @path = path
      @per_test_coverage = per_test_coverage
      @reuse_context = reuse_context
      @provenance = provenance
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
    # @param run_id [String, nil] one history entry per mutant and run: a
    #   second write of the same run replaces the entry its checkpoint wrote.
    # rubocop:disable Metrics/ParameterLists -- one keyword per recorded fact
    def record(result, version:, recorded_at: Time.now, operators: nil, full_scan: false, run_id: nil)
      # rubocop:enable Metrics/ParameterLists
      recorded_at = recorded_at.getutc
      write do |db|
        insert_run(db, result, version, recorded_at) if full_run?(result)
        record_subject_scans(db, result, recorded_at, operators) if complete_scan?(result, full_scan, operators)
        upsert_mutants(db, result.mutants, UpsertContext.new(version:, recorded_at:, run_id:, operators:))
      end
    end

    # Persists verdicts while a run is in progress (ADR-19): mutant rows
    # only, never a run row. @return [Integer] how many mutants were written
    def checkpoint(mutants, version:, run_id:, operators: nil, recorded_at: Time.now)
      context = UpsertContext.new(version:, recorded_at: recorded_at.getutc, run_id:, operators:)
      write { |db| upsert_mutants(db, mutants, context) }
      Array(mutants).size
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

    attr_reader :per_test_coverage, :reuse_context, :provenance

    def verdict_from_row(row)
      return nil unless row && VerdictCache::CACHEABLE_STATUSES.include?(row["current_status"])
      return nil if row["subject_source_hash"].nil? || row["covered_tests_fingerprint"].nil?

      {
        status: row["current_status"].to_sym,
        subject_source_hash: row["subject_source_hash"],
        covered_tests_fingerprint: row["covered_tests_fingerprint"]
      }
    end

    def full_run?(result)
      authoritative = !result.respond_to?(:authoritative?) || result.authoritative?
      authoritative && !partial_rerun?(result)
    end

    def partial_rerun?(result)
      result.respond_to?(:partial_rerun?) && result.partial_rerun?
    end

    def upsert_mutants(db, mutants, context)
      Array(mutants).each { |mutant| upsert_mutant(db, mutant, context) }
    end

    def insert_run(db, result, version, recorded_at)
      db.execute(Sql::INSERT_RUN, insert_run_bindings(result, version, recorded_at))
    end

    def upsert_mutant(db, mutant, context)
      db.execute(
        Sql::UPSERT_MUTANT,
        upsert_mutant_bindings(mutant_history_data(db, mutant, context), context.operators)
      )
    end

    def count_mutants(mutants)
      mutants.each_with_object(Hash.new(0)) do |mutant, counts|
        counts[:total] += 1
        counts[mutant.status] += 1
      end
    end

    # Recipe stubs carry a precomputed id that cannot be recomputed from
    # their (absent) AST nodes.
    def stable_mutant_id(mutant)
      mutant.respond_to?(:stable_id) ? mutant.stable_id : MutantIdentity.stable_id(mutant)
    end

    def mutation_history_entry(mutant, context)
      entry = { version: context.version, status: mutant.status.to_s, recordedAt: context.recorded_at.iso8601 }
      context.run_id ? entry.merge(runId: context.run_id) : entry
    end

    def mutant_history_data(db, mutant, context)
      version = context.version
      recorded_at = context.recorded_at
      mutant_id = stable_mutant_id(mutant)
      existing = existing_mutant_row(db, mutant_id)
      history = append_history(existing_status_history(existing), mutation_history_entry(mutant, context))
      first_seen = first_seen_metadata(existing, version, recorded_at)

      {
        mutant_id:, version:, recorded_at:, mutant:, history:, existing_row: existing,
        first_seen_version: first_seen[:version], first_seen_at: first_seen[:at],
        days_alive: days_alive_since(first_seen[:at], recorded_at)
      }
    end

    # A later write of the same run replaces that run's entry.
    def append_history(history, entry)
      history.pop if entry[:runId] && history.last&.dig(:runId) == entry[:runId]
      history << entry
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
