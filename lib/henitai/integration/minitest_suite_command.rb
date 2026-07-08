# frozen_string_literal: true

module Henitai
  module Integration
    # Builds the argv used to run Minitest test files in an external Ruby
    # process, for Minitest#spawn_suite_process's baseline coverage bootstrap.
    class MinitestSuiteCommand
      def build(test_files)
        ["bundle", "exec", "ruby", "-I", "test",
         "-r", "henitai/minitest_simplecov",
         "-r", "henitai/minitest_coverage_hook",
         "-e", "ARGV.each { |f| require File.expand_path(f) }",
         *test_files]
      end
    end
  end
end
