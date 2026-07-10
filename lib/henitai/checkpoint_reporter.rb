# frozen_string_literal: true

module Henitai
  # Progress observer that flushes the canonical report to disk periodically
  # during a run, so a crash on a long run keeps partial results and the report
  # grows visibly mid-run instead of appearing only at the end (Gate 5).
  #
  # Each flush serialises only the mutants completed since the previous flush
  # and folds them into the on-disk JSON report. When HTML reporting is active,
  # the self-contained HTML report is regenerated from that merged JSON schema.
  # Reuses {Result#to_stryker_schema} and {CanonicalReportWriter}.
  #
  # On a full (authoritative) run the first flush replaces the report — wiping
  # entries left by earlier runs, including deleted files — and later flushes
  # merge their batch in. On a scoped/partial run every flush merges, matching
  # the end-of-run reporter's behaviour.
  class CheckpointReporter
    MONOTONIC = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }

    def initialize(config:, source_provider:, authoritative:, started_at: Time.now, clock: MONOTONIC)
      @config = config
      @source_provider = source_provider
      @authoritative = authoritative
      @started_at = started_at
      @clock = clock
      @batch = []
      @last_flush_at = clock.call
      @flushed = false
    end

    def progress(mutant, **)
      @batch << mutant
      flush! if due?
    end

    private

    def due?
      return false if @batch.empty?

      @batch.size >= @config.checkpoint_every ||
        (@clock.call - @last_flush_at) >= @config.checkpoint_interval
    end

    def flush!
      merged_schema = CanonicalReportWriter.write(
        build_schema(@batch),
        path: canonical_path,
        authoritative: @authoritative && !@flushed
      )
      write_html(merged_schema) if html_reporter?
      @flushed = true
      @batch = []
      @last_flush_at = @clock.call
    end

    def build_schema(mutants)
      Result.new(
        mutants: mutants,
        started_at: @started_at,
        finished_at: Time.now,
        thresholds: @config.thresholds,
        source_provider: @source_provider,
        authoritative: @authoritative
      ).to_stryker_schema
    end

    def canonical_path
      File.join(@config.reports_dir, "mutation-report.json")
    end

    def html_reporter?
      Array(@config.reporters).map(&:to_s).include?("html")
    end

    def write_html(schema)
      Reporter::Html.new(config: @config).report_schema(schema)
    end
  end
end
