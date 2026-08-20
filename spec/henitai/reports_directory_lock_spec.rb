# frozen_string_literal: true

require "json"
require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::ReportsDirectoryLock do
  it "creates the reports directory and records the current owner while locked" do
    Dir.mktmpdir do |dir|
      reports_dir = File.join(dir, "nested", "..", "reports")
      lock_path = File.join(File.expand_path(reports_dir), ".henitai-run.lock")
      metadata = nil

      described_class.new(reports_dir:).synchronize do
        metadata = JSON.parse(File.read(lock_path))
      end

      expect(
        pid: metadata.fetch("pid"),
        started_at: Time.iso8601(metadata.fetch("started_at")).class,
        lock_file_persisted: File.exist?(lock_path)
      ).to eq(pid: Process.pid, started_at: Time, lock_file_persisted: true)
    end
  end

  # A forked mutant child inherits this handle, and the flock lives on the
  # shared open file description. Registering it lets the child close its copy
  # right after fork, so an orphaned child cannot pin the lock open.
  describe "inherited fd registration" do
    it "registers the lock handle while the lock is held" do
      Dir.mktmpdir do |reports_dir|
        registered = nil

        described_class.new(reports_dir:).synchronize do
          registered = Henitai::InheritedFdRegistry.registered.map { |io| io.path if io.respond_to?(:path) }
        end

        expect(registered).to include(File.join(reports_dir, ".henitai-run.lock"))
      end
    end

    it "unregisters the lock handle after the block returns" do
      Dir.mktmpdir do |reports_dir|
        described_class.new(reports_dir:).synchronize { nil }

        expect(Henitai::InheritedFdRegistry.registered).to be_empty
      end
    end

    it "unregisters the lock handle when the block raises" do
      Dir.mktmpdir do |reports_dir|
        begin
          described_class.new(reports_dir:).synchronize { raise "boom" }
        rescue RuntimeError
          # The raise is the point; the assertion is about cleanup after it.
        end

        expect(Henitai::InheritedFdRegistry.registered).to be_empty
      end
    end
  end

  it "replaces stale owner metadata after acquiring the lock" do
    Dir.mktmpdir do |reports_dir|
      lock_path = File.join(reports_dir, ".henitai-run.lock")
      File.write(lock_path, JSON.generate(pid: 123, started_at: "2000-01-01T00:00:00Z"))

      described_class.new(reports_dir:).synchronize do
        metadata = JSON.parse(File.read(lock_path))

        expect(metadata.fetch("pid")).to eq(Process.pid)
      end
    end
  end

  it "rejects a second lock for the same reports directory" do
    Dir.mktmpdir do |reports_dir|
      lock = described_class.new(reports_dir:)

      lock.synchronize do
        expect { described_class.new(reports_dir:).synchronize { nil } }
          .to raise_error(
            Henitai::ConcurrentRunError,
            /another henitai run is active.*\(pid #{Process.pid}\)/
          )
      end
    end
  end

  it "flags a dead recorded owner so orphaned lock holders are diagnosable" do
    Dir.mktmpdir do |reports_dir|
      lock_path = File.join(reports_dir, ".henitai-run.lock")
      File.write(lock_path, JSON.generate(pid: 4217, started_at: "2026-07-12T21:20:34+02:00"))
      allow(Process).to receive(:kill).with(0, 4217).and_raise(Errno::ESRCH)

      File.open(lock_path, File::RDWR) do |file|
        file.flock(File::LOCK_EX)

        expect { described_class.new(reports_dir:).synchronize { nil } }
          .to raise_error(
            Henitai::ConcurrentRunError,
            /recorded owner pid 4217 is not running.*orphaned child/m
          )
      end
    end
  end

  it "keeps the plain contention message when the recorded owner is alive" do
    Dir.mktmpdir do |reports_dir|
      lock = described_class.new(reports_dir:)

      lock.synchronize do
        # Anchored at end-of-message: no dead-owner hint appended.
        expect { described_class.new(reports_dir:).synchronize { nil } }
          .to raise_error(Henitai::ConcurrentRunError, /use a separate reports_dir or wait\z/)
      end
    end
  end

  it "reports an unknown owner for non-object metadata" do
    Dir.mktmpdir do |reports_dir|
      lock_path = File.join(reports_dir, ".henitai-run.lock")
      File.write(lock_path, "[]")

      File.open(lock_path, File::RDWR) do |file|
        file.flock(File::LOCK_EX)

        expect { described_class.new(reports_dir:).synchronize { nil } }
          .to raise_error(Henitai::ConcurrentRunError, /\(pid unknown\)/)
      end
    end
  end
end
