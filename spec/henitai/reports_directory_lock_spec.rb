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
end
