# frozen_string_literal: true

require "fileutils"
require "json"

module Henitai
  module Integration
    # Carries a mutant child's report to the parent through a small JSON file
    # next to the child's logs. The parent clears the file before each fork so
    # a retry can never read the previous attempt's report.
    #
    # The child also keeps a running-file marker next to the report: the test
    # file it is executing. A timeout leaves the marker behind, so the parent
    # learns which file hung.
    class ChildReportStore
      RUNNING_SUFFIX = ".running"

      def write(path, data)
        return unless path

        write_atomically(path, JSON.generate(data))
        nil
      end

      def read(path)
        return unless path && File.exist?(path)

        JSON.parse(File.read(path))
      rescue JSON::ParserError
        nil
      end

      def write_running(report_path, file)
        return unless report_path

        write_atomically(running_path(report_path), file.to_s)
        nil
      end

      def read_running(report_path)
        return unless report_path && File.exist?(running_path(report_path))

        File.read(running_path(report_path))
      end

      def clear(path)
        return nil unless path

        FileUtils.rm_f([path, running_path(path)])
        nil
      end

      private

      def running_path(report_path) = "#{report_path}#{RUNNING_SUFFIX}"

      def write_atomically(path, content)
        FileUtils.mkdir_p(File.dirname(path))
        temp_path = "#{path}.#{Process.pid}.tmp"
        File.write(temp_path, content)
        File.rename(temp_path, path)
      end
    end
  end
end
