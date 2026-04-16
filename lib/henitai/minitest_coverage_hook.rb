# frozen_string_literal: true

# Injected by henitai into the Minitest baseline subprocess to collect
# per-test line coverage. Must be required after henitai/minitest_simplecov
# so that Coverage is already running when the reporter takes snapshots.

require "minitest"
require "henitai/minitest_coverage_reporter"

Minitest.extensions << "henitai_coverage"

# Henitai per-test coverage plugin for Minitest.
module Minitest
  def self.plugin_henitai_coverage_init(_options)
    reporter.reporters << Henitai::MinitestCoverageReporter.new
  end
end
