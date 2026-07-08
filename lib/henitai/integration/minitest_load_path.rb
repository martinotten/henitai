# frozen_string_literal: true

module Henitai
  module Integration
    # Ensures the current project's test/ directory is on $LOAD_PATH, for
    # Minitest#run_mutant/#spawn_mutant. Idempotent: safe to call repeatedly.
    module MinitestLoadPath
      def self.ensure!
        test_dir = File.expand_path("test")
        $LOAD_PATH.unshift(test_dir) unless $LOAD_PATH.include?(test_dir)
      end
    end
  end
end
