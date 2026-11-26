# frozen_string_literal: true

require_relative "rspec_child_runner"

module Henitai
  module Integration
    # Lets the fork server (ADR-15) boot the RSpec environment once. The
    # booted runner stays in the server; every forked mutant process then runs
    # its own subset of the loaded example groups.
    module RspecPreload
      # Kept as an alias: callers rescue RspecPreload::PreloadError, and the
      # runner that raises it is a separate collaborator.
      PreloadError = RspecChildRunner::PreloadError

      def fork_server_supported?
        true
      end

      # Loads RSpec, its configured requires (spec_helper, rails_helper, ...)
      # and the given spec files, without activating a mutant or running a
      # test. Coverage startup is suppressed before anything loads, as it is
      # in every mutant child.
      #
      # @raise [PreloadError] when a spec file failed to load
      # @return [RspecChildRunner::Preloaded] the booted runner, which the
      #   forked mutant processes inherit through +rspec_child_runner+
      def preload_environment(test_files)
        CoverageRuntimeSuppressors.suppress_simplecov!
        CoverageRuntimeSuppressors.suppress_coverage!
        subprocess_env.each { |key, value| ENV[key] = value }
        require "rspec/core"
        ::RSpec.configuration.fail_if_no_examples = true
        @rspec_child_runner = rspec_child_runner.preload(test_files)
      end
    end
  end
end
