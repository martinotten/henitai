# frozen_string_literal: true

require "rspec/core"
require "henitai/coverage_formatter"

RSpec::Core::Formatters.register(
  Henitai::CoverageFormatter,
  :example_finished,
  :dump_summary
)
