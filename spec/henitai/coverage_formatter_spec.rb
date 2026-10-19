# frozen_string_literal: true

require "json"
require "spec_helper"
require "stringio"
require "tmpdir"

RSpec.describe Henitai::CoverageFormatter do
  def build_notification(file_path, run_time: 0.25, status: :passed)
    example = Struct.new(:metadata, :execution_result).new(
      { file_path: file_path },
      Struct.new(:run_time, :status).new(run_time, status)
    )
    Struct.new(:example).new(example)
  end

  def outcomes_path
    Henitai::TestFileOutcomes.report_path(ENV.fetch("HENITAI_REPORTS_DIR", "coverage"))
  end

  def summary(errors_outside_of_examples_count: 0)
    Struct.new(:errors_outside_of_examples_count).new(errors_outside_of_examples_count)
  end

  it "marks the outcomes as having an unattributed failure for errors outside examples" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        formatter = described_class.new(StringIO.new)
        allow(Coverage).to receive(:peek_result).and_return({})

        formatter.dump_summary(summary(errors_outside_of_examples_count: 1))

        expect(JSON.parse(File.read(outcomes_path))).to eq("outcomes" => {}, "unattributed_failures" => true)
      end
    end
  end

  it "attributes an after(:context) hook error to the open group's spec file" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        formatter = described_class.new(StringIO.new)
        allow(Coverage).to receive(:peek_result).and_return({})
        group = Struct.new(:metadata).new({ absolute_file_path: File.expand_path("spec/h_spec.rb") })

        formatter.example_group_started(Struct.new(:group).new(group))
        formatter.message(Struct.new(:message).new("\nAn error occurred in an `after(:context)` hook.\n"))
        formatter.example_group_finished(Struct.new(:group).new(group))
        formatter.dump_summary(summary(errors_outside_of_examples_count: 1))

        expect(JSON.parse(File.read(outcomes_path))).to eq(
          "outcomes" => { File.expand_path("spec/h_spec.rb") => "failed" }
        )
      end
    end
  end

  it "writes per-file outcomes, marking files with a failed example" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        formatter = described_class.new(StringIO.new)
        allow(Coverage).to receive(:peek_result).and_return({})

        formatter.example_finished(build_notification("spec/a_spec.rb", status: :failed))
        formatter.example_finished(build_notification("spec/b_spec.rb"))
        formatter.dump_summary(summary)

        expect(JSON.parse(File.read(outcomes_path))).to eq(
          "outcomes" => {
            File.expand_path("spec/a_spec.rb") => "failed",
            File.expand_path("spec/b_spec.rb") => "passed"
          }
        )
      end
    end
  end

  it "writes the outcomes file even when no coverage was collected" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        described_class.new(StringIO.new).dump_summary(summary)

        expect(JSON.parse(File.read(outcomes_path))).to eq("outcomes" => {})
      end
    end
  end

  def report_path
    File.join(ENV.fetch("HENITAI_REPORTS_DIR", "coverage"), "henitai_per_test.json")
  end

  def with_env(key, value)
    original = ENV.fetch(key, nil)
    ENV[key] = value
    yield
  ensure
    if original.nil?
      ENV.delete(key)
    else
      ENV[key] = original
    end
  end

  def coverage_snapshot(source_lines:)
    {
      File.expand_path("lib/sample.rb") => {
        "lines" => source_lines
      }
    }
  end

  it "writes nested per-test coverage data to the report path" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        formatter = described_class.new(StringIO.new)
        notification = build_notification("spec/models/sample_spec.rb")

        allow(Coverage).to receive(:peek_result).and_return(
          coverage_snapshot(source_lines: [nil, 1, 0, 3])
        )

        formatter.example_finished(notification)
        formatter.dump_summary(summary)

        expect(JSON.parse(File.read(report_path))).to eq(
          "spec/models/sample_spec.rb" => {
            "coverage" => { File.expand_path("lib/sample.rb") => [2, 4] },
            "duration" => 0.25
          }
        )
      end
    end
  end

  it "marks the end of boot when the first example starts" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        boot_clock = Henitai::SuiteBootClock.new(started_at: 10.0, clock: -> { 11.5 })
        formatter = described_class.new(StringIO.new, boot_clock:)

        allow(Coverage).to receive(:peek_result).and_return(
          coverage_snapshot(source_lines: [nil, 1])
        )

        formatter.example_started(build_notification("spec/models/sample_spec.rb"))
        formatter.example_finished(build_notification("spec/models/sample_spec.rb"))
        formatter.dump_summary(summary)

        boot_path = File.join(File.dirname(report_path), Henitai::PerTestCoverageCollector::BOOT_FILE_NAME)
        expect(JSON.parse(File.read(boot_path))).to eq("boot_seconds" => 1.5)
      end
    end
  end

  it "creates the output directory when needed" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        formatter = described_class.new(StringIO.new)
        notification = build_notification("spec/models/sample_spec.rb")

        allow(Coverage).to receive(:peek_result).and_return(
          coverage_snapshot(source_lines: [nil, 1, 0])
        )

        formatter.example_finished(notification)
        formatter.dump_summary(summary)

        expect(File).to exist(report_path)
      end
    end
  end

  it "writes the report under ENV-configured output dir" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        formatter = described_class.new(StringIO.new)
        notification = build_notification("spec/models/sample_spec.rb")
        reports_dir = File.join(dir, "custom-reports")

        with_env("HENITAI_REPORTS_DIR", reports_dir) do
          allow(Coverage).to receive(:peek_result).and_return(
            coverage_snapshot(source_lines: [nil, 1, 0])
          )

          formatter.example_finished(notification)
          formatter.dump_summary(summary)
        end

        expect(File).to exist(File.join(reports_dir, "henitai_per_test.json"))
      end
    end
  end

  it "handles the real Coverage.peek_result shape with symbol-keyed hashes" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        formatter = described_class.new(StringIO.new)
        notification = build_notification("spec/models/sample_spec.rb")

        allow(Coverage).to receive(:peek_result).and_return(
          File.expand_path("lib/sample.rb") => {
            lines: [nil, 1, 0, 3],
            branches: {},
            methods: {}
          }
        )

        formatter.example_finished(notification)
        formatter.dump_summary(summary)

        expect(JSON.parse(File.read(report_path))).to eq(
          "spec/models/sample_spec.rb" => {
            "coverage" => { File.expand_path("lib/sample.rb") => [2, 4] },
            "duration" => 0.25
          }
        )
      end
    end
  end

  it "canonicalizes relative source file keys when writing the report" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        formatter = described_class.new(StringIO.new)
        notification = build_notification("spec/models/sample_spec.rb")

        allow(Coverage).to receive(:peek_result).and_return(
          "lib/sample.rb" => [nil, 1, 0, 3]
        )

        formatter.example_finished(notification)
        formatter.dump_summary(summary)

        expect(JSON.parse(File.read(report_path))).to eq(
          "spec/models/sample_spec.rb" => {
            "coverage" => { File.expand_path("lib/sample.rb") => [2, 4] },
            "duration" => 0.25
          }
        )
      end
    end
  end

  it "warns once to stderr when coverage is unavailable" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        formatter = described_class.new(StringIO.new)

        # Other examples exercise child-run suppression in-process; the
        # module flag would leak into this one, so pin it off.
        allow(Henitai::Integration::CoverageRuntimeSuppressors)
          .to receive(:active?).and_return(false)
        notification = build_notification("spec/models/sample_spec.rb")

        allow(Coverage).to receive(:peek_result).and_raise(RuntimeError)

        expect do
          formatter.example_finished(notification)
          formatter.example_finished(notification)
          formatter.dump_summary(summary)
        end.to output(
          "Per-test coverage unavailable; skipping coverage formatter output\n"
        ).to_stderr
      end
    end
  end

  it "does not write a report when coverage is unavailable" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        formatter = described_class.new(StringIO.new)
        notification = build_notification("spec/models/sample_spec.rb")

        allow(Coverage).to receive(:peek_result).and_raise(RuntimeError)

        formatter.example_finished(notification)
        formatter.dump_summary(summary)

        expect(File.exist?("coverage/henitai_per_test.json")).to be(false)
      end
    end
  end
end
