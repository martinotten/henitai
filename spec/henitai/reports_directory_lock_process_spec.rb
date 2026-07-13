# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::ReportsDirectoryLock do
  def with_held_lock(reports_dir)
    ready_pipe = IO.pipe
    release_pipe = IO.pipe
    holder_pid = spawn_lock_holder(reports_dir, ready_pipe, release_pipe)
    ready_pipe.last.close
    release_pipe.first.close
    ready_pipe.first.read
    yield holder_pid
  ensure
    release_pipe&.last&.close
    Process.wait(holder_pid) if holder_pid
    ready_pipe&.first&.close
  end

  def spawn_lock_holder(reports_dir, ready_pipe, release_pipe)
    Process.fork do
      ready_pipe.first.close
      release_pipe.last.close
      described_class.new(reports_dir:).synchronize do
        ready_pipe.last.write("ready")
        ready_pipe.last.close
        release_pipe.first.read
      end
      Process.exit!(0)
    end
  end

  def acquire_in_child(reports_dir)
    reader, writer = IO.pipe
    pid = Process.fork do
      reader.close
      described_class.new(reports_dir:).synchronize { writer.write("acquired") }
      writer.close
      Process.exit!(0)
    end
    writer.close
    reader.read
  ensure
    reader&.close
    Process.wait(pid) if pid
  end

  it "fails immediately with owner diagnostics while another process holds the lock" do
    Dir.mktmpdir do |reports_dir|
      with_held_lock(reports_dir) do |holder_pid|
        expect { described_class.new(reports_dir:).synchronize { nil } }.to raise_error(
          Henitai::ConcurrentRunError,
          "another henitai run is active in #{reports_dir} " \
          "(pid #{holder_pid}); use a separate reports_dir or wait"
        )
      end
    end
  end

  it "treats canonical path aliases as the same reports directory" do
    Dir.mktmpdir do |dir|
      reports_dir = File.join(dir, "reports")
      alias_path = File.join(reports_dir, "..", "reports", ".")

      with_held_lock(reports_dir) do
        expect { described_class.new(reports_dir: alias_path).synchronize { nil } }.to raise_error(
          Henitai::ConcurrentRunError,
          /active in #{Regexp.escape(File.expand_path(reports_dir))}/
        )
      end
    end
  end

  it "allows different reports directories concurrently" do
    Dir.mktmpdir do |dir|
      with_held_lock(File.join(dir, "first")) do
        acquired = false
        described_class.new(reports_dir: File.join(dir, "second")).synchronize do
          acquired = true
        end

        expect(acquired).to be(true)
      end
    end
  end

  it "uses an unknown pid when owner metadata cannot be read" do
    Dir.mktmpdir do |reports_dir|
      with_held_lock(reports_dir) do
        File.write(File.join(reports_dir, ".henitai-run.lock"), "not json")

        expect { described_class.new(reports_dir:).synchronize { nil } }.to raise_error(
          Henitai::ConcurrentRunError,
          /\(pid unknown\)/
        )
      end
    end
  end

  it "releases the lock after successful completion" do
    Dir.mktmpdir do |reports_dir|
      expect([acquire_in_child(reports_dir), acquire_in_child(reports_dir)]).to eq(
        %w[acquired acquired]
      )
    end
  end

  it "releases the lock when the synchronized operation raises" do
    Dir.mktmpdir do |reports_dir|
      error = begin
        described_class.new(reports_dir:).synchronize { raise "boom" }
      rescue RuntimeError => e
        e
      end

      expect([error.message, acquire_in_child(reports_dir)]).to eq(%w[boom acquired])
    end
  end
end
