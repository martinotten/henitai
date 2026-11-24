# frozen_string_literal: true

module Henitai
  module Integration
    # Orders RSpec example groups by the position of their spec file in the
    # list handed to the child. The sort is stable: groups from one file keep
    # RSpec's own order, and groups from files not in the list come last.
    class RspecFileOrder
      # @param group [RSpec::Core::ExampleGroup] a top-level example group
      # @return [String] the group's absolute spec file path
      def self.file_of(group)
        metadata = group.metadata
        metadata[:absolute_file_path] || File.expand_path(metadata[:file_path])
      end

      # @param test_files [Array<String>] spec files in the order to run them
      def initialize(test_files)
        expanded = test_files.map { |file| File.expand_path(file) }.uniq
        @positions = expanded.each_with_index.to_h
      end

      # @param groups [Array<RSpec::Core::ExampleGroup>] groups in RSpec's order
      # @return [Array<RSpec::Core::ExampleGroup>] groups sorted by file position
      def sort(groups)
        groups.each_with_index
              .sort_by { |group, index| [position(group), index] }
              .map(&:first)
      end

      private

      def position(group)
        @positions.fetch(self.class.file_of(group), @positions.size)
      end
    end
  end
end
