# frozen_string_literal: true

require "rspec/core"
require "henitai/coverage_formatter"

RSpec::Core::Formatters.register(
  Henitai::CoverageFormatter,
  :example_started,
  :example_finished,
  :dump_summary
)
