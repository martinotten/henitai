# frozen_string_literal: true

# Injected by henitai into the Minitest baseline subprocess to collect
# line coverage and write it as a SimpleCov-compatible .resultset.json.
#
# Must be required before any application code is loaded so that Coverage
# tracking is active from the first line.

require "simplecov"

SimpleCov.coverage_dir(ENV.fetch("HENITAI_COVERAGE_DIR", "coverage"))
SimpleCov.start
