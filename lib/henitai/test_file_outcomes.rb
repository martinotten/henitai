# frozen_string_literal: true

require "fileutils"
require "json"

require_relative "per_test_coverage_collector"

module Henitai
  # Records per-test-file pass/fail outcomes from a test run.
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
        data.fetch("outcomes", {}).each do |file, outcome|
          outcomes.record(file, failed: outcome == "failed")
        end
      end
    rescue JSON::ParserError
      new
    end

    def initialize
      @failed = {}
    end

    def record(file, failed:)
      path = File.expand_path(file)
      @failed[path] = (@failed[path] || false) || failed
    end

    def failed_files
      @failed.select { |_file, failed| failed }.keys.sort
    end

    def outcomes
      @failed.transform_values { |failed| failed ? "failed" : "passed" }
    end

    def write(path)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate("outcomes" => outcomes))
    end
  end
end
