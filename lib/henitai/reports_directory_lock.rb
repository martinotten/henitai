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
        # Registered so a forked mutant child can close its inherited copy: the
        # flock lives on the shared open file description, so a child that
        # outlives its parent would otherwise keep this lock held. Unregistered
        # inside the File.open block, keeping the registration's lifetime a
        # subset of the handle's.
        InheritedFdRegistry.register(file)
        begin
          yield
        ensure
          InheritedFdRegistry.unregister(file)
        end
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
      message = "another henitai run is active in #{@reports_dir} " \
                "(pid #{pid}); use a separate reports_dir or wait"
      return message unless dead_owner?(pid)

      "#{message}. The recorded owner pid #{pid} is not running — an " \
        "orphaned child may still hold the lock " \
        "(check: lsof #{lock_path})"
    end

    # True only when the recorded owner pid provably no longer exists. EPERM
    # means the process is alive but owned by someone else — treated as alive.
    def dead_owner?(pid) = !ProcessLiveness.alive?(pid)

    def write_owner(file)
      file.rewind
      file.truncate(0)
      file.write(JSON.generate(pid: Process.pid, started_at: Time.now.iso8601))
      file.flush
    end
  end
end
