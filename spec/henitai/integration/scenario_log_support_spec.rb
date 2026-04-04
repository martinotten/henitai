# frozen_string_literal: true

require "spec_helper"

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

  it "redirects stdout and stderr to the child output files" do
    support = described_class.new
    stdout_file = instance_double(File)
    stderr_file = instance_double(File)
    calls = []

    allow($stdout).to receive(:reopen) { |file| calls << [:stdout, file] }
    allow($stderr).to receive(:reopen) { |file| calls << [:stderr, file] }

    support.redirect_child_output(
      stdout_file:,
      stderr_file:
    )

    expect(calls).to eq([[:stdout, stdout_file], [:stderr, stderr_file]])
  end

  it "restores stdout and stderr from the original streams" do
    support = described_class.new
    original_stdout = instance_double(IO)
    original_stderr = instance_double(IO)
    stdout_file = instance_double(File)
    stderr_file = instance_double(File)
    calls = []

    allow($stdout).to receive(:reopen) { |stream| calls << [:stdout, :reopen, stream] }
    allow($stderr).to receive(:reopen) { |stream| calls << [:stderr, :reopen, stream] }
    allow(stdout_file).to receive(:close) { calls << %i[stdout_file close] }
    allow(stderr_file).to receive(:close) { calls << %i[stderr_file close] }
    allow(original_stdout).to receive(:close) { calls << %i[original_stdout close] }
    allow(original_stderr).to receive(:close) { calls << %i[original_stderr close] }

    support.close_child_output(
      original_stdout:,
      original_stderr:,
      stdout_file:,
      stderr_file:
    )

    expect(calls).to eq(
      [
        [:stdout, :reopen, original_stdout],
        [:stderr, :reopen, original_stderr],
        %i[stdout_file close],
        %i[stderr_file close],
        %i[original_stdout close],
        %i[original_stderr close]
      ]
    )
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
