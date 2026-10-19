# frozen_string_literal: true

require "minitest"
require "henitai/per_test_coverage_collector"
require "henitai/test_file_outcomes"
require "henitai/minitest_result_file"

module Henitai
  # Minitest reporter that collects per-test line coverage deltas.
  #
  # Added to Minitest's reporter chain by the henitai_coverage plugin
  # (see minitest_coverage_hook.rb). Delegates accumulation and serialisation
  # to PerTestCoverageCollector so the JSON output format is identical to the
  # RSpec integration.
  class MinitestCoverageReporter < Minitest::Reporter
    def initialize(io = $stdout, options = {}, boot_clock: SuiteBootClock.from_env(ENV))
      super(io, options)
      @collector = PerTestCoverageCollector.new(boot_clock:)
      @outcomes = TestFileOutcomes.new
    end

    def prerecord(klass, name)
      super
      @collector.test_started
    end

    def record(result)
      super
      record_coverage(result)
      MinitestResultFile.record(@outcomes, result)
    end

    def report
      super
      @collector.write_report
      @outcomes.write(TestFileOutcomes.default_report_path)
    end

    private

    # A result without a resolvable file is skipped, so its coverage delta is
    # not attributed to the next recorded test.
    def record_coverage(result)
      file = MinitestResultFile.for(result)
      return @collector.skip_test unless file

      @collector.record_test(relative_to_pwd(file), duration: result.time)
    end

    def relative_to_pwd(path)
      prefix = "#{Dir.pwd}#{File::SEPARATOR}"
      path.start_with?(prefix) ? path.sub(prefix, "") : path
    end
  end
end
