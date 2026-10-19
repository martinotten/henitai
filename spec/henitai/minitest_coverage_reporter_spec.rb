# frozen_string_literal: true

require "json"
require "minitest"
require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::MinitestCoverageReporter do
  # CoverageBootstrapper sets HENITAI_REPORTS_DIR when running the baseline
  # suite, which redirects the collector's output away from the tmpdir used by
  # these tests. Clear it so write_report uses the default "coverage/" path.
  around do |example|
    original = ENV.delete("HENITAI_REPORTS_DIR")
    example.run
  ensure
    ENV["HENITAI_REPORTS_DIR"] = original if original
  end

  def build_result(absolute_path, time: 0.25)
    build_named_result("UnresolvableTest", [absolute_path, 5], time:)
  end

  def build_named_result(klass, source_location, time: 0.25)
    Struct.new(:klass, :source_location, :time) do
      def passed? = true

      def skipped? = false
    end.new(klass, source_location, time)
  end

  def coverage_snapshot(source_lines:)
    {
      File.expand_path("lib/sample.rb") => { "lines" => source_lines }
    }
  end

  it "writes per-test coverage keyed by the project-relative test path" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        reporter = described_class.new

        allow(Coverage).to receive(:peek_result).and_return(
          coverage_snapshot(source_lines: [nil, 1, 0, 3])
        )

        reporter.record(build_result(File.join(Dir.pwd, "test", "sample_test.rb")))
        reporter.report

        report_path = File.join("coverage", "henitai_per_test.json")
        expect(JSON.parse(File.read(report_path))).to eq(
          "test/sample_test.rb" => {
            "coverage" => { File.expand_path("lib/sample.rb") => [2, 4] },
            "duration" => 0.25
          }
        )
      end
    end
  end

  it "marks the end of boot when the first test is prerecorded" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        boot_clock = Henitai::SuiteBootClock.new(started_at: 20.0, clock: -> { 23.0 })
        reporter = described_class.new(StringIO.new, boot_clock:)

        allow(Coverage).to receive(:peek_result).and_return(
          coverage_snapshot(source_lines: [nil, 1])
        )

        reporter.prerecord(Object, "test_sample")
        reporter.record(build_result(File.join(Dir.pwd, "test", "sample_test.rb")))
        reporter.report

        boot_path = File.join("coverage", Henitai::PerTestCoverageCollector::BOOT_FILE_NAME)
        expect(JSON.parse(File.read(boot_path))).to eq("boot_seconds" => 3.0)
      end
    end
  end

  it "does not write a report when no tests have been recorded" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        reporter = described_class.new

        reporter.report

        expect(File.exist?(File.join("coverage", "henitai_per_test.json"))).to be(false)
      end
    end
  end

  it "records no coverage and does not crash for a result without a source location" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        reporter = described_class.new

        allow(Coverage).to receive(:peek_result).and_return(
          coverage_snapshot(source_lines: [nil, 1])
        )

        reporter.record(build_named_result("UnresolvableTest", nil))
        reporter.report

        expect(File.exist?(File.join("coverage", "henitai_per_test.json"))).to be(false)
      end
    end
  end

  it "keys coverage by the file that defines the result's class, not the method's file" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        reporter = described_class.new
        class_file = Object.const_source_location("Henitai::MinitestCoverageReporter").first
        shared_file = File.join(Dir.pwd, "test", "shared_examples.rb")

        allow(Coverage).to receive(:peek_result).and_return(
          coverage_snapshot(source_lines: [nil, 1])
        )

        reporter.record(build_named_result("Henitai::MinitestCoverageReporter", [shared_file, 3]))
        reporter.report

        report = JSON.parse(File.read(File.join("coverage", "henitai_per_test.json")))
        expect(report.keys).to eq([class_file])
      end
    end
  end

  it "does not credit a skipped result's coverage to the next test" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        reporter = described_class.new
        snapshots = [
          coverage_snapshot(source_lines: [nil, 1, 0]),
          coverage_snapshot(source_lines: [nil, 1, 2])
        ]

        allow(Coverage).to receive(:peek_result).and_return(*snapshots)

        reporter.record(build_named_result("UnresolvableTest", nil))
        reporter.record(build_result(File.join(Dir.pwd, "test", "sample_test.rb")))
        reporter.report

        report = JSON.parse(File.read(File.join("coverage", "henitai_per_test.json")))
        expect(report.fetch("test/sample_test.rb").fetch("coverage")).to eq(File.expand_path("lib/sample.rb") => [3])
      end
    end
  end

  it "passes an out-of-project path through unchanged as the test key" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        reporter = described_class.new
        outside_path = "/other/project/test/sample_test.rb"

        allow(Coverage).to receive(:peek_result).and_return(
          coverage_snapshot(source_lines: [nil, 1, 0])
        )

        reporter.record(build_result(outside_path))
        reporter.report

        report_path = File.join("coverage", "henitai_per_test.json")
        report = JSON.parse(File.read(report_path))
        expect(report.keys).to eq([outside_path])
      end
    end
  end
end
