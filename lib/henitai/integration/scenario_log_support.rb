# frozen_string_literal: true

require "fileutils"

module Henitai
  module Integration
    # Shared helpers for capturing stdout/stderr from child test processes and
    # for reading and combining the captured log files afterwards.
    class ScenarioLogSupport
      # Env var carrying the per-stream capture cap (bytes) into forked
      # children. Set by the execution engine from Configuration#max_log_bytes.
      MAX_LOG_BYTES_ENV = "HENITAI_MAX_LOG_BYTES"
      DEFAULT_MAX_LOG_BYTES = 5_000_000
      DRAIN_CHUNK_BYTES = 65_536

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

      # Captures via a pipe drained by a background thread that writes to the
      # log file only up to +max_log_bytes+ and then discards the overflow.
      # A runaway mutant (e.g. one that recurses henitai into itself and spews
      # backtraces) can otherwise fill hundreds of MB per child; draining past
      # the cap keeps the writer from blocking on a full pipe.
      def open_child_output(log_paths)
        FileUtils.mkdir_p(File.dirname(log_paths[:log_path]))
        cap = max_log_bytes
        output_files = {
          original_stdout: stdout_stream.dup,
          original_stderr: stderr_stream.dup,
          stdout: open_capped_stream(log_paths[:stdout_path], cap),
          stderr: open_capped_stream(log_paths[:stderr_path], cap)
        }
        redirect_child_output(output_files)
        output_files
      end

      def close_child_output(output_files)
        return unless output_files

        restore_child_output(output_files)
        finish_capped_stream(output_files[:stdout])
        finish_capped_stream(output_files[:stderr])
        output_files[:original_stdout]&.close
        output_files[:original_stderr]&.close
      end

      # One capture channel: a pipe whose read end is drained (capped) into the
      # log file by a dedicated thread. Returns the pieces close needs.
      def open_capped_stream(path, cap)
        file = File.new(path, "w")
        file.sync = true
        reader, writer = IO.pipe
        thread = Thread.new { drain_capped(reader, file, cap) }
        { file:, reader:, writer:, thread: }
      end

      def drain_capped(reader, file, cap)
        written = 0
        truncated = false
        loop do
          chunk = reader.readpartial(DRAIN_CHUNK_BYTES)
          next unless written < cap

          slice = chunk.byteslice(0, cap - written)
          file.write(slice)
          written += slice.bytesize
          next unless written >= cap && !truncated

          file.write("\n[henitai] output truncated at #{cap} bytes\n")
          truncated = true
        end
      rescue IOError
        # EOFError (a subclass) on writer close, or a closed pipe: draining done.
        nil
      end

      def finish_capped_stream(stream)
        return unless stream

        stream[:writer].close
        stream[:thread].join
        stream[:reader].close
        stream[:file].close
      end

      def redirect_child_output(output_files)
        reopen_child_output_stream(stdout_stream, output_files[:stdout][:writer])
        reopen_child_output_stream(stderr_stream, output_files[:stderr][:writer])
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

      def max_log_bytes
        raw = ENV.fetch(MAX_LOG_BYTES_ENV, nil)
        value = raw.to_i
        value.positive? ? value : DEFAULT_MAX_LOG_BYTES
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
