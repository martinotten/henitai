# frozen_string_literal: true

require "fileutils"
require "json"

require_relative "per_test_coverage_collector"

module Henitai
  # Records per-test-file pass/fail outcomes from a test run.
  #
  # A failure that happens outside any example (a spec file that fails to
  # load, a `before(:suite)` hook, a Minitest result without a usable file)
  # cannot be pinned to a test file. It is recorded separately as an
  # unattributed failure so consumers never mistake the run for a clean one.
  class TestFileOutcomes
    REPORT_FILE_NAME = "henitai_suite_outcomes.json"

    def self.report_path(reports_dir)
      File.join(reports_dir, REPORT_FILE_NAME)
    end

    def self.default_report_path
      report_path(ENV.fetch(PerTestCoverageCollector::REPORT_DIR_ENV, "coverage"))
    end

    def self.load(path)
      return new unless File.exist?(path)

      data = JSON.parse(File.read(path))
      new.tap do |outcomes|
        outcomes.record_unattributed_failure if data["unattributed_failures"]
        data.fetch("outcomes", {}).each do |file, outcome|
          outcomes.record(file, failed: outcome == "failed")
        end
      end
    rescue JSON::ParserError
      new
    end

    def initialize
      @failed = {}
      @unattributed_failures = false
    end

    def record(file, failed:)
      path = File.expand_path(file)
      @failed[path] = (@failed[path] || false) || failed
    end

    def record_unattributed_failure
      @unattributed_failures = true
    end

    def unattributed_failures?
      @unattributed_failures
    end

    def failed_files
      @failed.select { |_file, failed| failed }.keys.sort
    end

    def outcomes
      @failed.transform_values { |failed| failed ? "failed" : "passed" }
    end

    def write(path)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate(payload))
    end

    private

    def payload
      data = { "outcomes" => outcomes }
      data["unattributed_failures"] = true if @unattributed_failures
      data
    end
  end
end
