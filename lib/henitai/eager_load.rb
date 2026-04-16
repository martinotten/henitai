# frozen_string_literal: true

require "henitai"

# Force all autoloaded constants to load so mutation testing tools
# (e.g. mutant) can discover subjects via ObjectSpace.
SIDE_EFFECT_FILES = %w[minitest_simplecov.rb minitest_coverage_hook.rb rspec_coverage_formatter.rb].freeze

Dir[File.join(__dir__, "**/*.rb")].each do |f|
  require f unless SIDE_EFFECT_FILES.any? { |name| f.end_with?(name) }
end
