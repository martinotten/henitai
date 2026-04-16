# frozen_string_literal: true

require "minitest"
require "henitai/per_test_coverage_collector"

module Henitai
  # Minitest reporter that collects per-test line coverage deltas.
  #
  # Added to Minitest's reporter chain by the henitai_coverage plugin
  # (see minitest_coverage_hook.rb). Delegates accumulation and serialisation
  # to PerTestCoverageCollector so the JSON output format is identical to the
  # RSpec integration.
  class MinitestCoverageReporter < Minitest::Reporter
    def initialize(io = $stdout, options = {})
      super
      @collector = PerTestCoverageCollector.new
    end

    def record(result)
      super
      @collector.record_test(relative_to_pwd(result.source_location.first))
    end

    def report
      super
      @collector.write_report
    end

    private

    def relative_to_pwd(path)
      prefix = "#{Dir.pwd}#{File::SEPARATOR}"
      path.start_with?(prefix) ? path.sub(prefix, "") : path
    end
  end
end
