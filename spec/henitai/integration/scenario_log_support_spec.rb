# frozen_string_literal: true

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

  describe "#read_log_file" do
    it "returns an empty string when the path does not exist" do
      Dir.mktmpdir do |dir|
        missing = File.join(dir, "missing.log")

        expect(described_class.new.read_log_file(missing)).to eq("")
      end
    end

    it "returns the file contents when the path exists" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "present.log")
        File.write(path, "hello world")

        expect(described_class.new.read_log_file(path)).to eq("hello world")
      end
    end
  end

  describe "#combined_log" do
    it "joins both streams when both are present" do
      result = described_class.new.combined_log("out", "err")

      expect(result).to eq("stdout:\nout\nstderr:\nerr")
    end

    it "includes only stdout when stderr is empty" do
      result = described_class.new.combined_log("out", "")

      expect(result).to eq("stdout:\nout")
    end

    it "includes only stderr when stdout is empty" do
      result = described_class.new.combined_log("", "err")

      expect(result).to eq("stderr:\nerr")
    end

    it "returns an empty string when both streams are empty" do
      expect(described_class.new.combined_log("", "")).to eq("")
    end
  end

  describe "#write_combined_log" do
    it "creates the parent directory and writes the combined log" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "nested", "combined.log")

        described_class.new.write_combined_log(path, "out", "err")

        expect(File.read(path)).to eq("stdout:\nout\nstderr:\nerr")
      end
    end
  end

  describe "#open_child_output and #close_child_output" do
    def log_paths(dir)
      {
        log_path: File.join(dir, "logs", "combined.log"),
        stdout_path: File.join(dir, "logs", "stdout.log"),
        stderr_path: File.join(dir, "logs", "stderr.log")
      }
    end

    it "creates the log directory, opens files, and redirects child output" do
      Dir.mktmpdir do |dir|
        support = described_class.new
        paths = log_paths(dir)

        output_files = support.open_child_output(paths)

        expect(File.directory?(File.join(dir, "logs"))).to be(true)
      ensure
        support.close_child_output(output_files)
      end
    end

    it "returns the stream handles from open_child_output" do
      Dir.mktmpdir do |dir|
        support = described_class.new
        output_files = support.open_child_output(log_paths(dir))

        expect(output_files.keys).to contain_exactly(
          :original_stdout, :original_stderr, :stdout, :stderr
        )
      ensure
        support.close_child_output(output_files)
      end
    end

    it "writes redirected stdout to its log file then restores the stream" do
      Dir.mktmpdir do |dir|
        support = described_class.new
        paths = log_paths(dir)
        output_files = support.open_child_output(paths)
        output_files[:stdout][:writer].write("captured out")
        support.close_child_output(output_files)

        expect(File.read(paths[:stdout_path])).to eq("captured out")
      end
    end

    it "caps captured stdout at max_log_bytes and appends a truncation marker", :aggregate_failures do
      with_env(described_class::MAX_LOG_BYTES_ENV, "100") do
        Dir.mktmpdir do |dir|
          support = described_class.new
          paths = log_paths(dir)
          output_files = support.open_child_output(paths)
          output_files[:stdout][:writer].write("a" * 5_000)
          support.close_child_output(output_files)

          content = File.read(paths[:stdout_path])
          expect(content).to start_with("a" * 100)
          expect(content).not_to start_with("a" * 101)
          expect(content).to include("truncated at 100 bytes")
        end
      end
    end

    it "does not append a truncation marker when output stays under the cap" do
      with_env(described_class::MAX_LOG_BYTES_ENV, "1000") do
        Dir.mktmpdir do |dir|
          support = described_class.new
          paths = log_paths(dir)
          output_files = support.open_child_output(paths)
          output_files[:stdout][:writer].write("small")
          support.close_child_output(output_files)

          expect(File.read(paths[:stdout_path])).to eq("small")
        end
      end
    end

    it "uses the default cap for a non-positive environment value" do
      with_env(described_class::MAX_LOG_BYTES_ENV, "-1") do
        Dir.mktmpdir do |dir|
          support = described_class.new
          paths = log_paths(dir)
          output_files = support.open_child_output(paths)
          output_files[:stdout][:writer].write("small")
          support.close_child_output(output_files)

          expect(File.read(paths[:stdout_path])).to eq("small")
        end
      end
    end

    it "does nothing when close_child_output is given nil" do
      expect { described_class.new.close_child_output(nil) }.not_to raise_error
    end
  end
end
