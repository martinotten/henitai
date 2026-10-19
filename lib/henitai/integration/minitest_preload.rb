# frozen_string_literal: true

require_relative "minitest_autorun"
require_relative "minitest_load_path"
require_relative "rails_environment_preloader"

module Henitai
  module Integration
    # Fork-server support for the Minitest integration (ADR-15): the server
    # loads the environment and the union of the run's test files once, without
    # running anything; each mutant process then runs only its own files.
    module MinitestPreload
      def fork_server_supported?
        true
      end

      def preload_environment(test_files)
        MinitestAutorun.suppress!
        CoverageRuntimeSuppressors.suppress_simplecov!
        CoverageRuntimeSuppressors.suppress_coverage!
        subprocess_env.each { |key, value| ENV[key] = value }
        MinitestLoadPath.ensure!
        RailsEnvironmentPreloader.new.call
        test_files.each { |file| require File.expand_path(file) }
        @minitest_preloaded = true
        nil
      end
    end
  end
end
