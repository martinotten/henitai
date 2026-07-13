# frozen_string_literal: true

module Henitai
  # Recognizes directories holding henitai/SimpleCov *output* so dependency
  # scans can skip them. Detection requires artifact evidence — known output
  # files inside the directory — not just a conventional name: a directory
  # merely named reports/ or coverage/ may hold legitimate fixture input,
  # and wrongly excluding a real dependency would let an obsolete Survived
  # verdict be reused (unsound). Wrongly including junk merely re-runs.
  module GeneratedArtifacts
    # Evidence that a coverage/ directory is SimpleCov output.
    COVERAGE_MARKERS = %w[.resultset.json .last_run.json].freeze

    # Evidence that a reports/ directory is a henitai reports_dir.
    REPORT_MARKERS = %w[
      mutation-report.json
      mutation-report.html
      mutation-history.sqlite3
      mutation-history.json
      henitai_per_test.json
      henitai_dependency_manifest.json
      .henitai-run.lock
      mutation-logs
      mutation-coverage
    ].freeze

    module_function

    # True when the directory carries a generated-artifact name AND contains
    # evidence of actual output. Unreadable directories count as evidence-
    # free — they stay in the scan (conservative direction).
    def generated_dir?(path)
      case File.basename(path)
      when "coverage" then evidence?(path, COVERAGE_MARKERS)
      when "reports" then evidence?(path, REPORT_MARKERS)
      when "mutation-logs", "mutation-coverage" then per_mutant_evidence?(path)
      else false
      end
    end

    # Dir.each_child returns an Enumerator, which has no #intersect? —
    # Style/ArrayIntersect's autocorrect would produce a NoMethodError here.
    def evidence?(dir, markers)
      Dir.each_child(dir).any? { |entry| markers.include?(entry) } # rubocop:disable Style/ArrayIntersect
    rescue SystemCallError
      false
    end

    # Per-mutant scratch trees hold one entry per mutant (or baseline);
    # checked lazily — these directories can contain tens of thousands of
    # files, so never materialize the full listing.
    def per_mutant_evidence?(dir)
      Dir.each_child(dir).any? { |entry| entry.start_with?("mutant-", "baseline") }
    rescue SystemCallError
      false
    end
  end
end
