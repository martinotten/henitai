# frozen_string_literal: true

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

      def defined_in_wanted_file?(suite)
        suite.runnable_methods.any? do |name|
          location = suite.instance_method(name).source_location
          location && @wanted.include?(canonical(location.first))
        end
      rescue NotImplementedError, NameError
        false
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
