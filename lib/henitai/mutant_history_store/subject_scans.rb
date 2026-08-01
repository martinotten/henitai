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
      private

      # Partial reruns (`--survivors-from`) deliberately do not update the
      # baseline: they re-record a subset of a subject's mutants, and moving
      # the baseline would retire the ones they left alone.
      def record_subject_scans(db, result, recorded_at)
        subject_expressions(result).each do |expression|
          db.execute(Sql::UPSERT_SUBJECT_SCAN, [expression, recorded_at.iso8601])
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
