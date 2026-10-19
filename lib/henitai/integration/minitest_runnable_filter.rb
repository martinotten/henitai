# frozen_string_literal: true

require "henitai/minitest_result_file"

module Henitai
  module Integration
    # Narrows Minitest's registry of test classes to those defined in the given
    # test files, for a process that inherited the union of a run's test files
    # from the fork server (ADR-15). A class belongs to a file when one of its
    # test methods is defined there.
    class MinitestRunnableFilter
      def initialize(test_files)
        @wanted = test_files.to_set { |file| canonical(file) }
      end

      def apply!
        with_seed { ::Minitest::Runnable.runnables.select! { |suite| defined_in_wanted_file?(suite) } }
      end

      private

      # runnable_methods shuffles with Minitest.seed, which is unset before a run.
      def with_seed
        original = ::Minitest.seed
        ::Minitest.seed ||= 0
        yield
      ensure
        ::Minitest.seed = original
      end

      # A suite belongs to a file when its class is defined there, or when one
      # of its test methods is. The class file covers tests inherited from a
      # shared module, which report the module's file; the method check covers
      # a class reopened in another file.
      def defined_in_wanted_file?(suite)
        wanted_class_file?(suite) || method_in_wanted_file?(suite)
      rescue NotImplementedError, NameError
        false
      end

      def wanted_class_file?(suite)
        file = suite.name && MinitestResultFile.class_file_of(suite.name)
        !file.nil? && @wanted.include?(canonical(file))
      end

      def method_in_wanted_file?(suite)
        suite.runnable_methods.any? do |name|
          location = suite.instance_method(name).source_location
          location && @wanted.include?(canonical(location.first))
        end
      end

      # Symlinked temp or checkout directories must not make one file two paths.
      def canonical(path)
        File.realpath(path)
      rescue SystemCallError
        File.expand_path(path)
      end
    end
  end
end
