# frozen_string_literal: true

require "coverage"
Coverage.start(lines: true, branches: true, methods: true)

require "simplecov"
SimpleCov.coverage_dir(ENV.fetch("HENITAI_COVERAGE_DIR", "coverage"))
SimpleCov.start do
  add_filter "/spec/"
  enable_coverage :branch
end

require_relative "support/warning_silencer"
require "henitai"
Dir[File.join(__dir__, "support/**/*.rb")]
  .reject { |path| path.end_with?("_spec.rb") }
  .each { |path| require path }

SimpleCov.print_error_status = false
SimpleCov.formatters = [SimpleCov::Formatter::QuietHTMLFormatter]

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.include SpecSupport::NodeSearchHelper
  config.filter_run_when_matching :focus
  config.disable_monkey_patching!
  config.warnings = true
  config.order = :random
  Kernel.srand config.seed
end
