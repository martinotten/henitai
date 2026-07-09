# frozen_string_literal: true

require "fileutils"
require "json"
require "parser/current"
require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::CheckpointReporter do
  def build_config(reports_dir:, every: 100, interval: 30.0)
    Struct.new(:reports_dir, :thresholds, :checkpoint_every, :checkpoint_interval)
          .new(reports_dir, { high: 80, low: 60 }, every, interval)
  end

  def build_mutant(file:, status: :killed)
    node = Parser::CurrentRuby.parse("1 - 0")
    mutant = Henitai::Mutant.new(
      subject: Henitai::Subject.new(namespace: "Sample", method_name: "value"),
      operator: "ArithmeticOperator",
      nodes: { original: node, mutated: node },
      description: "replaced + with - (#{file})",
      location: { file:, start_line: 1, end_line: 1, start_col: 0, end_col: 5 }
    )
    mutant.status = status
    mutant
  end

  def canonical(reports_dir)
    JSON.parse(File.read(File.join(reports_dir, "mutation-report.json")))
  end

  # A clock that returns each queued value once, then holds the last one.
  def scripted_clock(values)
    queue = values.dup
    -> { queue.size > 1 ? queue.shift : queue.first }
  end

  it "does not write a report before the batch or interval threshold is reached" do
    Dir.mktmpdir do |dir|
      reporter = described_class.new(
        config: build_config(reports_dir: dir, every: 5, interval: 1_000.0),
        source_provider: ->(_f) { "" }, authoritative: true, clock: -> { 0.0 }
      )

      reporter.progress(build_mutant(file: "a.rb"))

      expect(File).not_to exist(File.join(dir, "mutation-report.json"))
    end
  end

  it "flushes once the batch reaches checkpoint_every mutants" do
    Dir.mktmpdir do |dir|
      reports_dir = File.join(dir, "reports")
      reporter = described_class.new(
        config: build_config(reports_dir:, every: 2, interval: 1_000.0),
        source_provider: ->(_f) { "" }, authoritative: true, clock: -> { 0.0 }
      )

      reporter.progress(build_mutant(file: "a.rb"))
      reporter.progress(build_mutant(file: "b.rb"))

      expect(canonical(reports_dir)["files"].keys).to contain_exactly("a.rb", "b.rb")
    end
  end

  it "flushes on the interval even when the batch is below checkpoint_every" do
    Dir.mktmpdir do |dir|
      reports_dir = File.join(dir, "reports")
      reporter = described_class.new(
        config: build_config(reports_dir:, every: 1_000, interval: 30.0),
        source_provider: ->(_f) { "" }, authoritative: true,
        clock: scripted_clock([0.0, 40.0])
      )

      reporter.progress(build_mutant(file: "a.rb"))

      expect(canonical(reports_dir)["files"].keys).to contain_exactly("a.rb")
    end
  end

  it "replaces prior findings on the first flush of a full run, then merges", :aggregate_failures do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        reports_dir = File.join(dir, "reports")
        FileUtils.mkdir_p(reports_dir)
        File.write(File.join(reports_dir, "mutation-report.json"), JSON.pretty_generate(
                                                                     { "schemaVersion" => "1.0",
                                                                       "files" => { "stale.rb" => {
                                                                         "mutants" => [{ "stableId" => "old" }]
                                                                       } } }
                                                                   ))
        %w[a.rb b.rb].each { |f| File.write(f, "1 - 0\n") }
        reporter = described_class.new(
          config: build_config(reports_dir:, every: 1, interval: 1_000.0),
          source_provider: ->(_f) { "" }, authoritative: true, clock: -> { 0.0 }
        )

        reporter.progress(build_mutant(file: "a.rb"))
        expect(canonical(reports_dir)["files"].keys).to contain_exactly("a.rb")

        reporter.progress(build_mutant(file: "b.rb"))
        expect(canonical(reports_dir)["files"].keys).to contain_exactly("a.rb", "b.rb")
      end
    end
  end

  it "merges every flush into the prior report on a scoped run" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        reports_dir = File.join(dir, "reports")
        FileUtils.mkdir_p(reports_dir)
        File.write("x.rb", "1 - 0\n")
        File.write(File.join(reports_dir, "mutation-report.json"), JSON.pretty_generate(
                                                                     { "schemaVersion" => "1.0",
                                                                       "files" => { "x.rb" => {
                                                                         "language" => "ruby", "source" => "",
                                                                         "mutants" => [{ "stableId" => "x1" }]
                                                                       } } }
                                                                   ))
        File.write("y.rb", "1 - 0\n")
        reporter = described_class.new(
          config: build_config(reports_dir:, every: 1, interval: 1_000.0),
          source_provider: ->(_f) { "" }, authoritative: false, clock: -> { 0.0 }
        )

        reporter.progress(build_mutant(file: "y.rb"))

        expect(canonical(reports_dir)["files"].keys).to contain_exactly("x.rb", "y.rb")
      end
    end
  end
end
