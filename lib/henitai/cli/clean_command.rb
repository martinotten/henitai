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
        removed_dirs = cleanup_dir_paths(config).select { |path| File.directory?(path) }
        removed_dirs.each { |path| FileUtils.rm_rf(path) }
        removed_files = cleanup_file_paths(config).select { |path| File.file?(path) }
        removed_files.each { |path| FileUtils.rm_f(path) }
        removed_dirs + removed_files
      end

      def cleanup_file_paths(config)
        REPORT_CLEANUP_PATHS.map { |relative_path| File.join(config.reports_dir, *relative_path) }
      end

      def cleanup_dir_paths(config)
        REPORT_CLEANUP_DIRS.map { |relative_path| File.join(config.reports_dir, *relative_path) }
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
