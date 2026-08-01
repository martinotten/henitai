# frozen_string_literal: true

module Henitai
  class MutantHistoryStore
    # SQL statements used by {MutantHistoryStore} to create the schema and
    # persist run/mutant rows in the SQLite history database.
    module Sql
      RUNS_TABLE = <<~SQL
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

      MUTANTS_TABLE = <<~SQL
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

      # When each subject was last mutated in full. Partial reruns
      # (`--survivors-from`) deliberately do not touch this table: they
      # record a subset of a subject's mutants, which must not make the rest
      # look retired.
      SUBJECT_SCANS_TABLE = <<~SQL
        CREATE TABLE IF NOT EXISTS subject_scans (
          subject_expression TEXT PRIMARY KEY,
          last_scanned_at TEXT NOT NULL
        );
      SQL

      UPSERT_SUBJECT_SCAN = <<~SQL
        INSERT INTO subject_scans (subject_expression, last_scanned_at)
        VALUES (?, ?)
        ON CONFLICT(subject_expression) DO UPDATE SET
          last_scanned_at = excluded.last_scanned_at
        WHERE excluded.last_scanned_at > subject_scans.last_scanned_at
      SQL

      # A mutant is retired when its own subject has been mutated in full
      # since it was last seen: the scan regenerated that subject's mutants
      # and this identity was not among them, so it can never match again.
      # Rows predating the subject_expression column (NULL) have no scan to
      # compare against and stay live — the conservative reading.
      LOAD_MUTANTS = <<~SQL
        SELECT mutants.*
        FROM mutants
        LEFT JOIN subject_scans
          ON subject_scans.subject_expression = mutants.subject_expression
        WHERE subject_scans.last_scanned_at IS NULL
           OR mutants.last_seen_at >= subject_scans.last_scanned_at
        ORDER BY mutants.first_seen_at, mutants.mutant_id
      SQL

      INSERT_RUN = <<~SQL
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

      # Nullable verdict-cache columns added after the initial release; see
      # MIGRATION_COLUMNS. Old rows keep NULL there, which the incremental
      # filter treats as never-reusable — the correct conservative behavior.
      MIGRATION_COLUMNS = {
        "subject_source_hash" => "TEXT",
        "covered_tests_fingerprint" => "TEXT",
        "subject_expression" => "TEXT"
      }.freeze

      UPSERT_MUTANT = <<~SQL
        INSERT INTO mutants (
          mutant_id,
          first_seen_version,
          first_seen_at,
          last_seen_version,
          last_seen_at,
          current_status,
          status_history,
          days_alive,
          subject_source_hash,
          covered_tests_fingerprint,
          subject_expression
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(mutant_id) DO UPDATE SET
          subject_expression = excluded.subject_expression,
          last_seen_version = excluded.last_seen_version,
          last_seen_at = excluded.last_seen_at,
          current_status = excluded.current_status,
          status_history = excluded.status_history,
          days_alive = excluded.days_alive,
          subject_source_hash = excluded.subject_source_hash,
          covered_tests_fingerprint = excluded.covered_tests_fingerprint
      SQL

      VERDICT_LOOKUP = <<~SQL
        SELECT current_status, subject_source_hash, covered_tests_fingerprint
        FROM mutants
        WHERE mutant_id = ?
      SQL
    end
  end
end
