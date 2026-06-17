# frozen_string_literal: true

require "fileutils"

module Henitai
  class CLI
    # Implements `henitai clean`: removes generated report artifacts listed in
    # {CLI::REPORT_CLEANUP_PATHS} and prints a deletion summary. Mixed into
    # {CLI}.
    module CleanCommand
      private

      def clean_command
        @command_halted = false
        options = parse_clean_options
        return if @command_halted

        config = load_config(options)
        removed_paths = cleanup_report_artifacts(config)
        puts clean_summary(removed_paths)
      rescue StandardError => e
        handle_run_error(e)
      end

      def cleanup_report_artifacts(config)
        removed_paths = report_cleanup_paths(config).select { |path| File.exist?(path) }
        removed_paths.each { |path| FileUtils.rm_f(path) }
        removed_paths
      end

      def report_cleanup_paths(config)
        REPORT_CLEANUP_PATHS.map do |relative_path|
          File.join(config.reports_dir, *relative_path)
        end
      end

      def clean_summary(removed_paths)
        return "No generated report artifacts to clean" if removed_paths.empty?

        format(
          "Removed %<count>s generated report artifact%<plural>s",
          count: removed_paths.length,
          plural: removed_paths.length == 1 ? "" : "s"
        )
      end
    end
  end
end
