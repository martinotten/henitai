# frozen_string_literal: true

require "henitai"

# Standalone entry point that forces every Henitai constant to load so external
# mutation tooling (e.g. mutant) can discover subjects via ObjectSpace.
#
# Usage:
#   ruby -r henitai/eager_load -e ""
#
# A bare `Dir[].each { require }` glob loads files in filesystem order, which
# does not respect dependency order: a child file that reopens an autoloaded
# constant (e.g. `class CLI` or `class Rspec < Base`) triggers the parent
# autoload before the child's own constants exist, raising NameError. To avoid
# that, first touch every constant in the autoload table so each entry-point
# file loads with its `require_relative` children in the correct order; only
# then glob the remaining files, by which point every base class and namespace
# is already defined and load order no longer matters.

# Files that run as side effects on load (test hooks and coverage formatters)
# and must therefore be skipped by the eager loader.
SIDE_EFFECT_FILES = %w[
  minitest_simplecov.rb
  minitest_coverage_hook.rb
  rspec_coverage_formatter.rb
].freeze

# Recursively force every autoloaded constant under a module to load, so nested
# namespaces (Operators::*, Mutant::*, CLI::*, Integration::*) load their bases
# before the glob below touches their files.
force_autoloads = lambda do |mod|
  mod.constants(false).each do |constant|
    value = mod.const_get(constant)
    force_autoloads.call(value) if value.is_a?(Module) && value.name&.start_with?("Henitai")
  end
end

force_autoloads.call(Henitai)

Dir[File.join(__dir__, "**/*.rb")].each do |file|
  require file unless SIDE_EFFECT_FILES.any? { |name| file.end_with?(name) }
end
