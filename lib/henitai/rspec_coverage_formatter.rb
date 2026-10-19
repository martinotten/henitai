# frozen_string_literal: true

require "rspec/core"
require "henitai/coverage_formatter"

RSpec::Core::Formatters.register(
  Henitai::CoverageFormatter,
  :example_started,
  :example_finished,
  :example_group_started,
  :example_group_finished,
  :message,
  :dump_summary
)
