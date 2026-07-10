# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

module Henitai
  # Coordinates exclusive access to a reports directory across processes.
  class ReportsDirectoryLock
    LOCK_FILENAME = ".henitai-run.lock"

    def initialize(reports_dir:)
      @reports_dir = File.expand_path(reports_dir)
    end

    def synchronize
      FileUtils.mkdir_p(@reports_dir)
      File.open(lock_path, File::RDWR | File::CREAT, 0o644) do |file|
        acquire(file)
        write_owner(file)
        yield
      end
    end

    private

    def lock_path
      File.join(@reports_dir, LOCK_FILENAME)
    end

    def acquire(file)
      return if file.flock(File::LOCK_EX | File::LOCK_NB)

      raise ConcurrentRunError, contention_message(owner_pid(file))
    end

    def owner_pid(file)
      file.rewind
      metadata = JSON.parse(file.read)
      pid = metadata["pid"] if metadata.is_a?(Hash)
      pid.is_a?(Integer) ? pid : "unknown"
    rescue JSON::ParserError, IOError, SystemCallError
      "unknown"
    end

    def contention_message(pid)
      "another henitai run is active in #{@reports_dir} " \
        "(pid #{pid}); use a separate reports_dir or wait"
    end

    def write_owner(file)
      file.rewind
      file.truncate(0)
      file.write(JSON.generate(pid: Process.pid, started_at: Time.now.iso8601))
      file.flush
    end
  end
end
