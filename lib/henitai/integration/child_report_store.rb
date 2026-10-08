# frozen_string_literal: true

require "fileutils"
require "json"

module Henitai
  module Integration
    # Carries a mutant child's report to the parent through a small JSON file
    # next to the child's logs. The parent clears the file before each fork so
    # a retry can never read the previous attempt's report.
    class ChildReportStore
      def write(path, data)
        return unless path

        FileUtils.mkdir_p(File.dirname(path))
        temp_path = "#{path}.#{Process.pid}.tmp"
        File.write(temp_path, JSON.generate(data))
        File.rename(temp_path, path)
        nil
      end

      def read(path)
        return unless path && File.exist?(path)

        JSON.parse(File.read(path))
      rescue JSON::ParserError
        nil
      end

      def clear(path)
        FileUtils.rm_f(path) if path
        nil
      end
    end
  end
end
