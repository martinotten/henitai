# frozen_string_literal: true

require "henitai/integration/minitest_autorun"
require "henitai/integration/minitest_outcome_reporter"
require "henitai/integration/minitest_runnable_filter"
require "henitai/test_file_outcomes"

module Henitai
  module Integration
    # Runs Minitest test files in-process and normalizes the result to an
    # exit code, for Minitest#run_tests during a single mutant activation.
    class MinitestTestRunner
      PLUGIN_NAME = "henitai_outcomes"

      # +preloaded+: the fork server already required the union of the run's
      # test files, so only the ones requested here are kept to run.
      def initialize(preloaded: false)
        @preloaded = preloaded
      end

      # Yields once the test files are required and before Minitest runs; a
      # falsy block result skips the run. Per-file outcomes are recorded into
      # +outcomes+ through a Minitest reporter plugin.
      def call(test_files, outcomes = TestFileOutcomes.new, &after_load)
        MinitestAutorun.suppress!
        load_tests(test_files)
        return 1 if after_load && !after_load.call

        install_outcome_plugin(outcomes)
        # @type var empty_args: Array[String]
        empty_args = []
        status = ::Minitest.run(empty_args)
        return status if status.is_a?(Integer)

        status == true ? 0 : 1
      end

      private

      def install_outcome_plugin(outcomes)
        ::Minitest.extensions << PLUGIN_NAME unless ::Minitest.extensions.include?(PLUGIN_NAME)
        init = :"plugin_#{PLUGIN_NAME}_init"
        ::Minitest.singleton_class.send(:remove_method, init) if ::Minitest.respond_to?(init)
        ::Minitest.define_singleton_method(init) do |_options|
          reporter.reporters << MinitestOutcomeReporter.new(outcomes)
        end
      end

      def load_tests(test_files)
        return MinitestRunnableFilter.new(test_files).apply! if @preloaded

        test_files.each { |file| require File.expand_path(file) }
      end
    end
  end
end
