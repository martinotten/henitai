# frozen_string_literal: true

module Henitai
  module Integration
    # Lets the fork server (ADR-15) boot the RSpec environment once. The
    # booted runner stays in the server; every forked mutant process then runs
    # its own subset of the loaded example groups.
    module RspecPreload
      class PreloadError < StandardError; end

      def fork_server_supported?
        true
      end

      # Loads RSpec, its configured requires (spec_helper, rails_helper, ...)
      # and the given spec files, without activating a mutant or running a
      # test. Coverage startup is suppressed before anything loads, as it is
      # in every mutant child.
      #
      # @raise [PreloadError] when a spec file failed to load
      def preload_environment(test_files)
        CoverageRuntimeSuppressors.suppress_simplecov!
        CoverageRuntimeSuppressors.suppress_coverage!
        subprocess_env.each { |key, value| ENV[key] = value }
        require "rspec/core"
        ::RSpec.configuration.fail_if_no_examples = true
        runner = prepare_rspec_runner(test_files)
        raise PreloadError, "the spec files failed to load" unless rspec_loaded_cleanly?

        @preloaded_runner = runner
        nil
      end
    end
  end
end
