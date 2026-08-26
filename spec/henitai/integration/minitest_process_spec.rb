# frozen_string_literal: true

require "rbconfig"
require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::Integration::Minitest do
  # The suite child spawns a grandchild and then outlives its own timeout. Only
  # a group-wide signal reaches both; signalling the direct pid alone would
  # leave the grandchild running, and signalling a group that was never created
  # raises ESRCH and leaves the whole tree alive.
  # Long enough that a run which merely waits the suite out instead of killing
  # it cannot pass inside the deadline below.
  def suite_sleep_seconds = 120

  def suite_script(marker_path)
    <<~RUBY
      pid = Process.spawn(#{RbConfig.ruby.dump}, "-e", "sleep #{suite_sleep_seconds}")
      File.write(#{marker_path.dump}, pid.to_s)
      sleep #{suite_sleep_seconds}
    RUBY
  end

  def wait_for_marker(path)
    50.times do
      return Integer(File.read(path)) if File.exist?(path) && !File.empty?(path)

      sleep 0.1
    end
    raise "grandchild never reported its pid"
  end

  def alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end

  def dead_within_grace?(pid)
    50.times do
      return true unless alive?(pid)

      sleep 0.1
    end
    false
  end

  def force_kill(pid)
    Process.kill(:SIGKILL, pid)
  rescue Errno::ESRCH, Errno::EPERM
    nil
  end

  it "kills the whole suite process group when the baseline times out" do
    grandchild_pid = nil

    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        integration = described_class.new
        marker = File.join(dir, "grandchild.pid")
        allow(integration).to receive(:suite_command).and_return(
          [RbConfig.ruby, "-e", suite_script(marker)]
        )

        # Generous enough that a slow interpreter boot cannot beat the timeout
        # to the marker file; the no-fix case still runs into the deadline.
        thread = Thread.new { integration.run_suite([], timeout: 5.0) }
        grandchild_pid = wait_for_marker(marker)
        elapsed = measure { thread.join }

        # Both halves matter: a parent that fails to signal the group blocks in
        # `reap_child` until the suite finishes on its own, so it eventually
        # sees a dead tree -- two minutes late.
        expect([dead_within_grace?(grandchild_pid), elapsed < 30]).to eq([true, true])
      end
    end
  ensure
    force_kill(grandchild_pid) if grandchild_pid
  end

  def measure
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
  end
end
