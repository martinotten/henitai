# frozen_string_literal: true

require "fileutils"

module Henitai
  module Integration
    # Shared helpers for capturing stdout/stderr from child test processes and
    # for reading and combining the captured log files afterwards.
    class ScenarioLogSupport
      def capture_child_output(log_paths)
        output_files = open_child_output(log_paths)
        yield
      ensure
        close_child_output(output_files)
      end

      def with_coverage_dir(mutant_id)
        original_coverage_dir = ENV.fetch("HENITAI_COVERAGE_DIR", nil)
        ENV["HENITAI_COVERAGE_DIR"] = mutation_coverage_dir(mutant_id)
        yield
      ensure
        if original_coverage_dir.nil?
          ENV.delete("HENITAI_COVERAGE_DIR")
        else
          ENV["HENITAI_COVERAGE_DIR"] = original_coverage_dir
        end
      end

      def open_child_output(log_paths)
        FileUtils.mkdir_p(File.dirname(log_paths[:log_path]))
        output_files = build_child_output_files(log_paths)
        sync_child_output_files(output_files)
        redirect_child_output(output_files)
        output_files
      end

      def close_child_output(output_files)
        return unless output_files

        restore_child_output(output_files)
        close_child_output_files(output_files)
      end

      def build_child_output_files(log_paths)
        {
          original_stdout: stdout_stream.dup,
          original_stderr: stderr_stream.dup,
          stdout_file: File.new(log_paths[:stdout_path], "w"),
          stderr_file: File.new(log_paths[:stderr_path], "w")
        }
      end

      def sync_child_output_files(output_files)
        output_files[:stdout_file].sync = true
        output_files[:stderr_file].sync = true
      end

      def redirect_child_output(output_files)
        reopen_child_output_stream(stdout_stream, output_files[:stdout_file])
        reopen_child_output_stream(stderr_stream, output_files[:stderr_file])
        $stdout = stdout_stream
        $stderr = stderr_stream
      end

      def restore_child_output(output_files)
        reopen_child_output_stream(stdout_stream, output_files[:original_stdout])
        reopen_child_output_stream(stderr_stream, output_files[:original_stderr])
        $stdout = stdout_stream
        $stderr = stderr_stream
      end

      def reopen_child_output_stream(stream, original_stream)
        stream.reopen(original_stream) if original_stream
      end

      def close_child_output_files(output_files)
        %i[stdout_file stderr_file original_stdout original_stderr].each do |key|
          output_files[key]&.close
        end
      end

      def read_log_file(path)
        return "" unless File.exist?(path)

        File.read(path)
      end

      def write_combined_log(path, stdout, stderr)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, combined_log(stdout, stderr))
      end

      def combined_log(stdout, stderr)
        [
          (stdout.empty? ? nil : "stdout:\n#{stdout}"),
          (stderr.empty? ? nil : "stderr:\n#{stderr}")
        ].compact.join("\n")
      end

      private

      def mutation_coverage_dir(mutant_id)
        reports_dir = ENV.fetch("HENITAI_REPORTS_DIR", "reports")
        File.join(reports_dir, "mutation-coverage", mutant_id.to_s)
      end

      def stdout_stream
        @stdout_stream ||= IO.for_fd(1)
      end

      def stderr_stream
        @stderr_stream ||= IO.for_fd(2)
      end
    end
  end
end
