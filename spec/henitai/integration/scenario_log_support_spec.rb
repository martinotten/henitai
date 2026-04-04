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
      described_class.new.with_coverage_dir("mutant-1") do
        expect(ENV.fetch("HENITAI_COVERAGE_DIR")).to eq(
          File.join("reports", "mutation-coverage", "mutant-1")
        )
      end

      expect(ENV.fetch("HENITAI_COVERAGE_DIR")).to eq("existing-dir")
    end
  end

  it "removes the coverage dir when none existed before" do
    with_env("HENITAI_COVERAGE_DIR", nil) do
      described_class.new.with_coverage_dir("mutant-2") do
        expect(ENV.fetch("HENITAI_COVERAGE_DIR")).to eq(
          File.join("reports", "mutation-coverage", "mutant-2")
        )
      end

      expect(ENV).not_to have_key("HENITAI_COVERAGE_DIR")
    end
  end

  it "uses the configured reports dir for mutation coverage" do
    with_env("HENITAI_REPORTS_DIR", "tmp/reports") do
      described_class.new.with_coverage_dir("mutant-3") do
        expect(ENV.fetch("HENITAI_COVERAGE_DIR")).to eq(
          File.join("tmp/reports", "mutation-coverage", "mutant-3")
        )
      end
    end
  end

  it "redirects stdout and stderr to the child output files" do
    support = described_class.new
    stdout_file = instance_double(File)
    stderr_file = instance_double(File)

    expect($stdout).to receive(:reopen).with(stdout_file)
    expect($stderr).to receive(:reopen).with(stderr_file)

    support.redirect_child_output(
      stdout_file:,
      stderr_file:
    )
  end

  it "restores stdout and stderr from the original streams" do
    support = described_class.new
    original_stdout = instance_double(IO)
    original_stderr = instance_double(IO)
    stdout_file = instance_double(File)
    stderr_file = instance_double(File)

    expect($stdout).to receive(:reopen).with(original_stdout)
    expect($stderr).to receive(:reopen).with(original_stderr)
    expect(stdout_file).to receive(:close)
    expect(stderr_file).to receive(:close)
    expect(original_stdout).to receive(:close)
    expect(original_stderr).to receive(:close)

    support.close_child_output(
      original_stdout:,
      original_stderr:,
      stdout_file:,
      stderr_file:
    )
  end

  it "does not reopen a stream when no original stream is available" do
    support = described_class.new
    stream = instance_double(IO)

    expect(stream).not_to receive(:reopen)

    support.reopen_child_output_stream(stream, nil)
  end

  it "marks both child output files as sync" do
    support = described_class.new
    stdout_file = instance_double(File)
    stderr_file = instance_double(File)

    expect(stdout_file).to receive(:sync=).with(true)
    expect(stderr_file).to receive(:sync=).with(true)

    support.sync_child_output_files(
      stdout_file:,
      stderr_file:
    )
  end
end
