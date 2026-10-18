# frozen_string_literal: true

module Henitai
  module Integration
    # Runs Minitest test files in-process and normalizes the result to an
    # exit code, for Minitest#run_tests during a single mutant activation.
    class MinitestTestRunner
      # Yields once the test files are required and before Minitest runs; a
      # falsy block result skips the run.
      def call(test_files, &after_load)
        suppress_autorun!
        test_files.each { |file| require File.expand_path(file) }
        return 1 if after_load && !after_load.call

        # @type var empty_args: Array[String]
        empty_args = []
        status = ::Minitest.run(empty_args)
        return status if status.is_a?(Integer)

        status == true ? 0 : 1
      end

      private

      def suppress_autorun!
        require "minitest"
        singleton_class = ::Minitest.singleton_class
        suppressor = @autorun_suppressor ||= Module.new.tap do |mod|
          mod.define_method(:autorun) { nil }
        end
        return if singleton_class.ancestors.include?(suppressor)

        singleton_class.prepend(suppressor)
        nil
      rescue LoadError, NameError
        nil
      end
    end
  end
end
