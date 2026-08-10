# frozen_string_literal: true

module Henitai
  class MutantHistoryStore
    # Tracks when each subject was last mutated in full, which is what lets
    # the trend export tell a retired mutant identity ("its subject was
    # regenerated and this id was not among the results") from one that was
    # merely out of scope ("no run has mutated that subject since").
    #
    # Without the per-subject baseline any narrow run — `--since`, a single
    # subject pattern — would retire every mutant it did not re-record.
    # Mixed into {MutantHistoryStore}.
    module SubjectScans
      # When each subject was last mutated in full. Partial reruns
      # (`--survivors-from`) deliberately do not touch this table: they
      # record a subset of a subject's mutants, which must not make the rest
      # look retired.
      # Keyed by operator set as well as subject: a `light` scan regenerates
      # only the light mutants, so it can speak for those and no others.
      SUBJECT_SCANS_TABLE = <<~SQL
        CREATE TABLE IF NOT EXISTS subject_scans (
          subject_expression TEXT NOT NULL,
          operators TEXT NOT NULL,
          last_scanned_at TEXT NOT NULL,
          PRIMARY KEY (subject_expression, operators)
        );
      SQL

      UPSERT_SUBJECT_SCAN = <<~SQL
        INSERT INTO subject_scans (subject_expression, operators, last_scanned_at)
        VALUES (?, ?, ?)
        ON CONFLICT(subject_expression, operators) DO UPDATE SET
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
         AND subject_scans.operators = mutants.operators
        WHERE subject_scans.last_scanned_at IS NULL
           OR mutants.last_seen_at >= subject_scans.last_scanned_at
        ORDER BY mutants.first_seen_at, mutants.mutant_id
      SQL

      private

      # subject_scans carries a composite primary key, which SQLite cannot add
      # by ALTER TABLE. The table is a derived retirement baseline, never a
      # record of anything: dropping it means "no subject has been scanned
      # yet", so the next export retires nothing until a full scan rebuilds it.
      # Losing it is conservative; migrating it in place is not possible.
      def migrate_subject_scans_table(db)
        columns = db.execute("PRAGMA table_info(subject_scans)").map { |row| row["name"] }
        return if columns.empty? || columns.include?("operators")

        db.execute("DROP TABLE subject_scans")
      end

      # Only a run that regenerated a subject's mutants in full may advance
      # its baseline. Three things narrow a run below that bar, and all three
      # must leave the baseline alone or they retire mutants they merely did
      # not produce:
      #
      #   - partial reruns (`--survivors-from`), which re-record only survivors
      #   - sampling (`mutation.sampling.ratio`), which cuts the generated set
      #     at generation time — this repo's own config samples at 0.05
      #   - a narrower operator set, handled by keying the scan on `operators`
      #     so a `light` scan never speaks for `full`-only mutants
      def record_subject_scans(db, result, recorded_at, operators)
        subject_expressions(result).each do |expression|
          db.execute(
            UPSERT_SUBJECT_SCAN,
            [expression, operators.to_s, recorded_at.iso8601]
          )
        end
      end

      def subject_expressions(result)
        Array(result.mutants).filter_map { |mutant| mutant_subject_expression(mutant) }.uniq
      end

      def mutant_subject_expression(mutant)
        mutant.subject&.expression
      end
    end
  end
end
