# frozen_string_literal: true

require "open3"
require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::Integration::ScenarioLogSupport do
  def with_env(key, value)
    original = ENV.fetch(key, nil)

    if value.nil?
      ENV.delete(key)
    else
      ENV[key] = value
    end

    yield
  ensure
    if original.nil?
      ENV.delete(key)
    else
      ENV[key] = original
    end
  end

  it "restores the original coverage dir after yielding" do
    with_env("HENITAI_COVERAGE_DIR", "existing-dir") do
      events = []

      described_class.new.with_coverage_dir("mutant-1") do
        events << ENV.fetch("HENITAI_COVERAGE_DIR")
      end

      events << ENV.fetch("HENITAI_COVERAGE_DIR")

      expect(events).to eq(
        [
          File.join("reports", "mutation-coverage", "mutant-1"),
          "existing-dir"
        ]
      )
    end
  end

  it "removes the coverage dir when none existed before" do
    with_env("HENITAI_COVERAGE_DIR", nil) do
      events = []

      described_class.new.with_coverage_dir("mutant-2") do
        events << ENV.fetch("HENITAI_COVERAGE_DIR")
      end

      events << ENV.key?("HENITAI_COVERAGE_DIR")

      expect(events).to eq(
        [
          File.join("reports", "mutation-coverage", "mutant-2"),
          false
        ]
      )
    end
  end

  it "uses the configured reports dir for mutation coverage" do
    with_env("HENITAI_REPORTS_DIR", "tmp/reports") do
      events = []

      described_class.new.with_coverage_dir("mutant-3") do
        events << ENV.fetch("HENITAI_COVERAGE_DIR")
      end

      expect(events).to eq([File.join("tmp/reports", "mutation-coverage", "mutant-3")])
    end
  end

  it "uses the real stdio objects even when the parent captures stdout" do
    script = <<~RUBY
      require "stringio"
      require "tmpdir"

      $stdout = StringIO.new
      $stderr = StringIO.new

      require "henitai"
      require "henitai/integration"

      support = Henitai::Integration::ScenarioLogSupport.new

      Dir.mktmpdir do |dir|
        support.send(
          :redirect_child_output,
          original_stdout: IO.for_fd(1).dup,
          original_stderr: IO.for_fd(2).dup,
          stdout_file: File.open(File.join(dir, "stdout.log"), "w"),
          stderr_file: File.open(File.join(dir, "stderr.log"), "w")
        )
      end
    RUBY

    stdout, stderr, status = Open3.capture3(
      "bundle",
      "exec",
      "ruby",
      "-I",
      "lib",
      "-e",
      script
    )

    expect(status.success?).to be(true), [stdout, stderr].reject(&:empty?).join("\n")
  end

  it "does not reopen a stream when no original stream is available" do
    support = described_class.new
    stream = instance_double(IO)
    calls = []

    allow(stream).to receive(:reopen) { |value| calls << value }

    support.reopen_child_output_stream(stream, nil)

    expect(calls).to be_empty
  end

  it "marks both child output files as sync" do
    support = described_class.new
    stdout_file = instance_double(File)
    stderr_file = instance_double(File)
    calls = []

    allow(stdout_file).to receive(:sync=) { |value| calls << [:stdout, value] }
    allow(stderr_file).to receive(:sync=) { |value| calls << [:stderr, value] }

    support.sync_child_output_files(
      stdout_file:,
      stderr_file:
    )

    expect(calls).to eq([[:stdout, true], [:stderr, true]])
  end
end
