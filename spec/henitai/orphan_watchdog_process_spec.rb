# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

# Real forks, so this file must be named *_process_spec.rb:
# bin/verify-process-free-specs excludes that pattern, and .henitai.yml keeps
# it out of mutant children.
#
# Shape of every example here: fork a stand-in parent A, have A fork a mutant
# child B through the production spawn path, kill A, then assert something
# about B. Deadlines are bounded and B is always killed in an ensure -- a spec
# about orphaned processes must not leak one.
RSpec.describe "Orphan watchdog process behavior" do # rubocop:disable RSpec/DescribeClass
  let(:poll_interval) { "0.05" }

  def wait_until(timeout: 5.0)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      return true if yield
      return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.025
    end
  end

  # Forks a stand-in parent that spawns one mutant child through the real
  # RspecProcessRunner#spawn_mutant, reports the child's pid, and then blocks
  # forever waiting to be killed.
  def with_orphaned_child(reports_dir: nil)
    reader, writer = IO.pipe
    parent_pid = fork_stand_in_parent(reader, writer, reports_dir)
    writer.close
    # Newline-delimited rather than read-to-EOF: the mutant child inherits its
    # own copy of the write end and never closes it, so EOF would never arrive
    # and both sides would deadlock.
    child_pid = Integer(reader.gets.chomp)

    Process.kill(:KILL, parent_pid)
    Process.wait(parent_pid)

    yield child_pid
  ensure
    reader&.close
    kill_quietly(child_pid)
  end

  def fork_stand_in_parent(reader, writer, reports_dir)
    Process.fork do
      reader.close
      ENV["HENITAI_CHILD_WATCHDOG_INTERVAL"] = poll_interval
      run_stand_in_parent(writer, reports_dir)
    end
  end

  def run_stand_in_parent(writer, reports_dir)
    body = lambda do
      handle = spawn_blocking_mutant
      # Flush before anything else: the spec cannot kill this process until it
      # knows the child pid, and an unflushed write would deadlock both sides.
      writer.puts(handle.pid)
      writer.flush
      writer.close
      sleep
    end

    if reports_dir
      Henitai::ReportsDirectoryLock.new(reports_dir:).synchronize(&body)
    else
      body.call
    end
  end

  # An integration double is not usable across a fork boundary, so the child's
  # work is a plain sleep supplied by a stub object.
  def spawn_blocking_mutant
    integration = Object.new
    integration.define_singleton_method(:run_in_child) { |**| sleep }
    mutant = Object.new
    mutant.define_singleton_method(:id) { "orphan-probe" }

    Henitai::Integration::RspecProcessRunner.new.spawn_mutant(
      integration, mutant:, test_files: [], log_paths: {}
    )
  end

  def kill_quietly(pid)
    return unless pid

    Process.kill(:KILL, pid)
    Process.wait(pid)
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  end

  it "exits a child whose parent was killed without warning" do
    with_orphaned_child do |child_pid|
      died = wait_until { !Henitai::ProcessLiveness.alive?(child_pid) }

      expect(died).to be(true)
    end
  end

  # The failure this reproduces: a surviving child inherited the parent's flock
  # handle, so the lock stayed held by a dead pid and every later run aborted
  # with ConcurrentRunError.
  it "releases the reports-directory lock when the holder is killed" do
    Dir.mktmpdir do |reports_dir|
      with_orphaned_child(reports_dir:) do |child_pid|
        wait_until { !Henitai::ProcessLiveness.alive?(child_pid) }

        expect { Henitai::ReportsDirectoryLock.new(reports_dir:).synchronize { nil } }
          .not_to raise_error
      end
    end
  end
end
