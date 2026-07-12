# frozen_string_literal: true

require "fileutils"
require "stringio"
require "spec_helper"
require "parser/current"
require "tmpdir"

RSpec.describe Henitai::Reporter::Terminal do
  def build_mutant(status:, survived: false, attributes: {})
    Struct.new(:status, :survived, :operator, :location, :original_node, :mutated_node) do
      def survived?
        survived
      end
    end.new(
      status,
      survived,
      attributes[:operator],
      attributes[:location],
      attributes[:original_node],
      attributes[:mutated_node]
    )
  end

  def build_config(thresholds: { high: 80, low: 60 })
    Struct.new(:thresholds, :all_logs).new(thresholds, false)
  end

  def build_config_with_logs(thresholds: { high: 80, low: 60 })
    Struct.new(:thresholds, :all_logs).new(thresholds, true)
  end

  def build_result(mutants:, scoring_summary:, duration:)
    Struct.new(:mutants, :scoring_summary, :duration) do
      def partial_rerun? = false
      def survivor_stats = nil
    end.new(
      mutants,
      scoring_summary,
      duration
    )
  end

  def build_scenario_result(status:, stdout:, stderr:, log_path:)
    FileUtils.mkdir_p(File.dirname(log_path))
    File.write(
      log_path,
      [
        stdout.empty? ? nil : "stdout:\n#{stdout}",
        stderr.empty? ? nil : "stderr:\n#{stderr}"
      ].compact.join("\n")
    )

    Henitai::ScenarioExecutionResult.new(
      status:,
      stdout:,
      stderr:,
      log_path:
    )
  end

  def capture_stdout
    original_stdout = $stdout
    stdout = StringIO.new
    $stdout = stdout
    yield stdout
    stdout
  ensure
    $stdout = original_stdout
  end

  def summary_row(label, value)
    "#{label.ljust(12)} #{value}"
  end

  def score_summary_line(
    mutation_score:,
    mutation_score_indicator:,
    equivalence_uncertainty:,
    color_code: nil
  )
    line = format(
      "MS %<ms>s | MSI %<msi>s | Equivalence uncertainty %<uncertainty>s",
      ms: mutation_score,
      msi: mutation_score_indicator,
      uncertainty: equivalence_uncertainty
    )
    return line unless color_code

    "\e[#{color_code}m#{line}\e[0m"
  end

  def parse_node(source)
    Parser::CurrentRuby.parse(source)
  end

  def survived_detail_mutant(file:, line:, operator:, original_source:, mutated_source:)
    build_mutant(
      status: :survived,
      survived: true,
      attributes: {
        operator:,
        location: { file:, start_line: line },
        original_node: parse_node(original_source),
        mutated_node: parse_node(mutated_source)
      }
    )
  end

  def unsupported_string_mutant
    node = Parser::AST::Node.new(:dstr, [])

    build_mutant(
      status: :survived,
      survived: true,
      attributes: {
        operator: "StringLiteral",
        location: { file: "lib/cli.rb", start_line: 12 },
        original_node: node,
        mutated_node: node
      }
    )
  end

  def first_survived_detail_mutant
    survived_detail_mutant(
      file: "lib/foo.rb",
      line: 12,
      operator: "ArithmeticOperator",
      original_source: "1",
      mutated_source: "2"
    )
  end

  def second_survived_detail_mutant
    survived_detail_mutant(
      file: "lib/bar.rb",
      line: 7,
      operator: "BooleanLiteral",
      original_source: "true",
      mutated_source: "false"
    )
  end

  def survived_detail_mutants
    [first_survived_detail_mutant, second_survived_detail_mutant]
  end

  def survived_detail_scoring_summary
    {
      mutation_score: 75.0,
      mutation_score_indicator: 12.5,
      equivalence_uncertainty: "~10-15% of live mutants"
    }
  end

  def build_survived_detail_result
    build_result(
      mutants: survived_detail_mutants,
      scoring_summary: survived_detail_scoring_summary,
      duration: 12.34
    )
  end

  it "prints progress glyphs for known statuses" do
    reporter = described_class.new(config: build_config)
    mutants = %i[killed survived timeout ignored].map { |status| build_mutant(status:) }

    expect { mutants.each { |mutant| reporter.progress(mutant) } }
      .to output("·STI").to_stdout
  end

  it "keeps killed mutant output quiet by default" do
    Dir.mktmpdir do |dir|
      reporter = described_class.new(config: build_config)
      scenario_result = build_scenario_result(
        status: :killed,
        stdout: "stdout noise\n",
        stderr: "stderr noise\n",
        log_path: File.join(dir, "mutant.log")
      )

      expect do
        reporter.progress(build_mutant(status: :killed), scenario_result:)
      end.to output("·").to_stdout
    end
  end

  it "flushes stdout when no logs are shown" do
    reporter = described_class.new(config: build_config)

    stdout = capture_stdout do |captured_stdout|
      allow(captured_stdout).to receive(:flush).and_call_original
      reporter.progress(build_mutant(status: :killed))
    end

    expect(stdout.string).to eq("·")
  end

  it "flushes stdout after printing a glyph without logs" do
    reporter = described_class.new(config: build_config)

    stdout = capture_stdout do |captured_stdout|
      allow(captured_stdout).to receive(:flush).and_call_original
      reporter.progress(build_mutant(status: :killed))
    end

    expect(stdout).to have_received(:flush)
  end

  it "prints the failure tail and flushes when logs are shown" do
    Dir.mktmpdir do |dir|
      reporter = described_class.new(config: build_config)
      scenario_result = build_scenario_result(
        status: :timeout,
        stdout: "stdout noise\n",
        stderr: "stderr noise\n",
        log_path: File.join(dir, "timeout.log")
      )

      stdout = capture_stdout do |captured_stdout|
        allow(captured_stdout).to receive(:flush).and_call_original
        reporter.progress(build_mutant(status: :timeout), scenario_result:)
      end

      expect(stdout.string).to include(
        "T",
        "log: #{File.join(dir, 'timeout.log')}",
        "stdout:\nstdout noise",
        "stderr:\nstderr noise"
      )
    end
  end

  it "flushes stdout after printing logs" do
    Dir.mktmpdir do |dir|
      reporter = described_class.new(config: build_config)
      scenario_result = build_scenario_result(
        status: :timeout,
        stdout: "stdout noise\n",
        stderr: "stderr noise\n",
        log_path: File.join(dir, "timeout.log")
      )

      stdout = capture_stdout do |captured_stdout|
        allow(captured_stdout).to receive(:flush).and_call_original
        reporter.progress(build_mutant(status: :timeout), scenario_result:)
      end

      expect(stdout).to have_received(:flush)
    end
  end

  it "prints a timeout tail and log path" do
    Dir.mktmpdir do |dir|
      reporter = described_class.new(config: build_config)
      stdout = (1..15).map { |index| format("stdout-%02d", index) }.join("\n")
      scenario_result = build_scenario_result(
        status: :timeout,
        stdout:,
        stderr: "",
        log_path: File.join(dir, "timeout.log")
      )

      expect do
        reporter.progress(build_mutant(status: :timeout), scenario_result:)
      end.to output(
        a_string_matching(
          /log: #{Regexp.escape(File.join(dir, 'timeout.log'))}.*stdout-15/m
        )
      ).to_stdout
    end
  end

  it "prints all captured logs when all_logs is enabled" do
    Dir.mktmpdir do |dir|
      reporter = described_class.new(config: build_config_with_logs)
      scenario_result = build_scenario_result(
        status: :killed,
        stdout: "stdout noise\n",
        stderr: "stderr noise\n",
        log_path: File.join(dir, "mutant.log")
      )

      expect do
        reporter.progress(build_mutant(status: :killed), scenario_result:)
      end.to output(
        a_string_matching(/log: .*mutant\.log/m)
          .and(a_string_including("stdout noise"))
          .and(a_string_including("stderr noise"))
      ).to_stdout
    end
  end

  it "does not print a glyph for unknown statuses" do
    reporter = described_class.new(config: build_config)

    expect { reporter.progress(build_mutant(status: :pending)) }.not_to output.to_stdout
  end

  it "falls back to the node type when unparsing unsupported strings" do
    reporter = described_class.new(config: build_config)
    mutant = unsupported_string_mutant
    allow(Unparser).to receive(:unparse).with(mutant.original_node).and_raise(Unparser::UnsupportedNodeError, "boom")
    allow(Unparser).to receive(:unparse).with(mutant.mutated_node).and_raise(Unparser::UnsupportedNodeError, "boom")
    result = build_result(
      mutants: [mutant],
      scoring_summary: survived_detail_scoring_summary,
      duration: 12.34
    )

    expect { reporter.report(result) }.to output(/dstr/).to_stdout
  end

  it "prints a summary table with score, counts, and duration" do
    reporter = described_class.new(config: build_config, color_enabled: true)
    result = build_result(
      mutants: %i[killed timeout no_coverage].map { |status| build_mutant(status:) },
      scoring_summary: {
        mutation_score: 75.0,
        mutation_score_indicator: 12.5,
        equivalence_uncertainty: "~10-15% of live mutants"
      },
      duration: 12.34
    )

    expected_output = <<~OUTPUT
      Mutation testing summary
      #{score_summary_line(
        mutation_score: '75.00%',
        mutation_score_indicator: '12.50%',
        equivalence_uncertainty: '~10-15% of live mutants',
        color_code: '33'
      )}
      #{summary_row('Killed', 1)}
      #{summary_row('Survived', 0)}
      #{summary_row('Timeout', 1)}
      #{summary_row('No coverage', 1)}
      #{summary_row('Duration', '12.34s')}
    OUTPUT

    expect { reporter.report(result) }.to output(expected_output).to_stdout
  end

  it "uses default thresholds when the config does not define any" do
    reporter = described_class.new(config: build_config(thresholds: nil), color_enabled: true)
    result = build_result(
      mutants: [],
      scoring_summary: {
        mutation_score: 81.0,
        mutation_score_indicator: 10.0,
        equivalence_uncertainty: nil
      },
      duration: 0.0
    )

    expected_output = <<~OUTPUT
      Mutation testing summary
      #{score_summary_line(
        mutation_score: '81.00%',
        mutation_score_indicator: '10.00%',
        equivalence_uncertainty: 'n/a',
        color_code: '32'
      )}
      #{summary_row('Killed', 0)}
      #{summary_row('Survived', 0)}
      #{summary_row('Timeout', 0)}
      #{summary_row('No coverage', 0)}
      #{summary_row('Duration', '0.00s')}
    OUTPUT

    expect { reporter.report(result) }.to output(expected_output).to_stdout
  end

  it "summarizes verdicts reused from history" do
    reporter = described_class.new(config: build_config, color_enabled: false)
    cached = Struct.new(:status) do
      def survived? = false
      def from_cache? = true
    end.new(:killed)
    non_cached = Struct.new(:status) do
      def survived? = false
      def from_cache? = false
    end.new(:killed)
    result = build_result(
      mutants: [cached, non_cached],
      scoring_summary: {
        mutation_score: 100.0,
        mutation_score_indicator: 100.0,
        equivalence_uncertainty: nil
      },
      duration: 1.0
    )

    expect { reporter.report(result) }.to output(
      a_string_including("1 of 2 verdicts reused from history (1 killed, 0 survived)")
    ).to_stdout
  end

  it "splits reused verdict counts by killed and survived" do
    reporter = described_class.new(config: build_config, color_enabled: false)
    # Detail-line rendering is exercised elsewhere; survived? is stubbed false
    # so this fake only feeds the status-based reuse counters.
    cached_mutant = Struct.new(:status) do
      def survived? = false
      def from_cache? = true
    end
    result = build_result(
      mutants: [cached_mutant.new(:killed), cached_mutant.new(:survived), cached_mutant.new(:killed)],
      scoring_summary: {
        mutation_score: 100.0,
        mutation_score_indicator: 100.0,
        equivalence_uncertainty: nil
      },
      duration: 1.0
    )

    expect { reporter.report(result) }.to output(
      a_string_including("3 of 3 verdicts reused from history (2 killed, 1 survived)")
    ).to_stdout
  end

  def build_result_with_executed_summary(executed_scoring_summary)
    Struct.new(:mutants, :scoring_summary, :duration, :executed_scoring_summary) do
      def partial_rerun? = false
      def survivor_stats = nil
    end.new(
      [],
      { mutation_score: 90.0, mutation_score_indicator: 80.0, equivalence_uncertainty: nil },
      1.0,
      executed_scoring_summary
    )
  end

  it "prints an executed-only score line when verdicts were reused" do
    reporter = described_class.new(config: build_config, color_enabled: false)
    result = build_result_with_executed_summary(
      { mutation_score: 75.0, mutation_score_indicator: 50.0 }
    )

    expect { reporter.report(result) }.to output(
      a_string_including("Executed-only MS 75.00% | MSI 50.00%")
    ).to_stdout
  end

  it "omits the executed-only score line when nothing was reused" do
    reporter = described_class.new(config: build_config, color_enabled: false)
    result = build_result_with_executed_summary(nil)

    expect { reporter.report(result) }.not_to output(
      a_string_including("Executed-only")
    ).to_stdout
  end

  it "prints a full summary when partial rerun status is unavailable" do
    reporter = described_class.new(config: build_config, color_enabled: false)
    result = Struct.new(:mutants, :scoring_summary, :duration).new(
      [],
      {
        mutation_score: 75.0,
        mutation_score_indicator: 12.5,
        equivalence_uncertainty: nil
      },
      1.5
    )

    expected_output = <<~OUTPUT
      Mutation testing summary
      #{score_summary_line(
        mutation_score: '75.00%',
        mutation_score_indicator: '12.50%',
        equivalence_uncertainty: 'n/a'
      )}
      #{summary_row('Killed', 0)}
      #{summary_row('Survived', 0)}
      #{summary_row('Timeout', 0)}
      #{summary_row('No coverage', 0)}
      #{summary_row('Duration', '1.50s')}
    OUTPUT

    expect { reporter.report(result) }.to output(expected_output).to_stdout
  end

  it "colors the score line green when the score meets the high threshold" do
    reporter = described_class.new(config: build_config, color_enabled: true)
    result = build_result(
      mutants: [],
      scoring_summary: {
        mutation_score: 80.0,
        mutation_score_indicator: 10.0,
        equivalence_uncertainty: nil
      },
      duration: 0.0
    )

    expected_output = <<~OUTPUT
      Mutation testing summary
      #{score_summary_line(
        mutation_score: '80.00%',
        mutation_score_indicator: '10.00%',
        equivalence_uncertainty: 'n/a',
        color_code: '32'
      )}
      #{summary_row('Killed', 0)}
      #{summary_row('Survived', 0)}
      #{summary_row('Timeout', 0)}
      #{summary_row('No coverage', 0)}
      #{summary_row('Duration', '0.00s')}
    OUTPUT

    expect { reporter.report(result) }.to output(expected_output).to_stdout
  end

  it "colors the score line yellow when the score meets the low threshold" do
    reporter = described_class.new(config: build_config, color_enabled: true)
    result = build_result(
      mutants: [],
      scoring_summary: {
        mutation_score: 60.0,
        mutation_score_indicator: 10.0,
        equivalence_uncertainty: nil
      },
      duration: 0.0
    )

    expected_output = <<~OUTPUT
      Mutation testing summary
      #{score_summary_line(
        mutation_score: '60.00%',
        mutation_score_indicator: '10.00%',
        equivalence_uncertainty: 'n/a',
        color_code: '33'
      )}
      #{summary_row('Killed', 0)}
      #{summary_row('Survived', 0)}
      #{summary_row('Timeout', 0)}
      #{summary_row('No coverage', 0)}
      #{summary_row('Duration', '0.00s')}
    OUTPUT

    expect { reporter.report(result) }.to output(expected_output).to_stdout
  end

  it "colors the score line red when the score is below the low threshold" do
    reporter = described_class.new(config: build_config, color_enabled: true)
    result = build_result(
      mutants: [],
      scoring_summary: {
        mutation_score: 50.0,
        mutation_score_indicator: 10.0,
        equivalence_uncertainty: nil
      },
      duration: 0.0
    )

    expected_output = <<~OUTPUT
      Mutation testing summary
      #{score_summary_line(
        mutation_score: '50.00%',
        mutation_score_indicator: '10.00%',
        equivalence_uncertainty: 'n/a',
        color_code: '31'
      )}
      #{summary_row('Killed', 0)}
      #{summary_row('Survived', 0)}
      #{summary_row('Timeout', 0)}
      #{summary_row('No coverage', 0)}
      #{summary_row('Duration', '0.00s')}
    OUTPUT

    expect { reporter.report(result) }.to output(expected_output).to_stdout
  end

  it "does not emit ANSI colors when color_enabled is false" do
    reporter = described_class.new(config: build_config, color_enabled: false)
    result = build_result(
      mutants: [],
      scoring_summary: {
        mutation_score: 80.0,
        mutation_score_indicator: 10.0,
        equivalence_uncertainty: nil
      },
      duration: 0.0
    )

    expected_output = <<~OUTPUT
      Mutation testing summary
      #{score_summary_line(
        mutation_score: '80.00%',
        mutation_score_indicator: '10.00%',
        equivalence_uncertainty: 'n/a'
      )}
      #{summary_row('Killed', 0)}
      #{summary_row('Survived', 0)}
      #{summary_row('Timeout', 0)}
      #{summary_row('No coverage', 0)}
      #{summary_row('Duration', '0.00s')}
    OUTPUT

    expect { reporter.report(result) }.to output(expected_output).to_stdout
  end

  it "prints n/a when the scoring summary does not include live mutants" do
    reporter = described_class.new(config: build_config, color_enabled: true)
    result = build_result(
      mutants: [],
      scoring_summary: {
        mutation_score: nil,
        mutation_score_indicator: nil,
        equivalence_uncertainty: nil
      },
      duration: 0.0
    )

    expected_output = <<~OUTPUT
      Mutation testing summary
      #{score_summary_line(
        mutation_score: 'n/a',
        mutation_score_indicator: 'n/a',
        equivalence_uncertainty: 'n/a'
      )}
      #{summary_row('Killed', 0)}
      #{summary_row('Survived', 0)}
      #{summary_row('Timeout', 0)}
      #{summary_row('No coverage', 0)}
      #{summary_row('Duration', '0.00s')}
    OUTPUT

    expect { reporter.report(result) }.to output(expected_output).to_stdout
  end

  it "prints survived mutant details after the summary block" do
    reporter = described_class.new(config: build_config, color_enabled: true)
    result = build_survived_detail_result

    expected_output = <<~OUTPUT
      Mutation testing summary
      #{score_summary_line(
        mutation_score: '75.00%',
        mutation_score_indicator: '12.50%',
        equivalence_uncertainty: '~10-15% of live mutants',
        color_code: '33'
      )}
      #{summary_row('Killed', 0)}
      #{summary_row('Survived', 2)}
      #{summary_row('Timeout', 0)}
      #{summary_row('No coverage', 0)}
      #{summary_row('Duration', '12.34s')}

      Survived mutants
      lib/foo.rb:12 ArithmeticOperator
      - 1
      + 2
      lib/bar.rb:7 BooleanLiteral
      - true
      + false
    OUTPUT

    expect { reporter.report(result) }.to output(expected_output).to_stdout
  end

  it "renders visible escapes for string literal survivors" do
    reporter = described_class.new(config: build_config, color_enabled: false)
    mutant = survived_detail_mutant(
      file: "lib/foo.rb",
      line: 3,
      operator: "StringLiteral",
      original_source: "\"\\n\"",
      mutated_source: "\"x\""
    )
    result = build_result(
      mutants: [mutant],
      scoring_summary: survived_detail_scoring_summary,
      duration: 1.0
    )

    expect { reporter.report(result) }.to output(
      a_string_including(%(- "\\n"))
        .and(a_string_including(%(+ "x")))
    ).to_stdout
  end

  describe "partial rerun" do
    def build_partial_result(survivor_stats: nil)
      klass = Struct.new(:mutants, :scoring_summary, :duration) do
        def partial_rerun? = true
        def survivor_stats = nil
      end
      instance = klass.new(
        [],
        { mutation_score: nil, mutation_score_indicator: nil, equivalence_uncertainty: nil },
        0.5
      )
      instance.define_singleton_method(:survivor_stats) { survivor_stats }
      instance
    end

    def build_partial_result_without_survivor_stats
      Struct.new(:mutants, :scoring_summary, :duration) do
        def partial_rerun? = true
      end.new(
        [],
        { mutation_score: nil, mutation_score_indicator: nil, equivalence_uncertainty: nil },
        0.5
      )
    end

    it "prints a partial rerun summary header" do
      reporter = described_class.new(config: build_config, color_enabled: false)
      result = build_partial_result

      expect { reporter.report(result) }.to output(/Partial survivor rerun/).to_stdout
    end

    it "prints a partial rerun summary when survivor_stats is unavailable" do
      reporter = described_class.new(config: build_config, color_enabled: false)
      result = build_partial_result_without_survivor_stats

      expected_output = <<~OUTPUT
        Partial survivor rerun
        #{summary_row('Survived', 0)}
        #{summary_row('Duration', '0.50s')}
      OUTPUT

      expect { reporter.report(result) }.to output(expected_output).to_stdout
    end

    it "includes survivor match stats when survivor_stats is present" do
      reporter = described_class.new(config: build_config, color_enabled: false)
      stats = { matched: 3, unmatched_count: 1, unmatched_ids: ["abc"],
                skipped_count: 0, drift_warning: false }
      result = build_partial_result(survivor_stats: stats)
      expected_output = <<~OUTPUT
        Partial survivor rerun
        #{summary_row('Survived', 0)}
        #{summary_row('Duration', '0.50s')}
        #{summary_row('Matched', 3)}
        #{summary_row('Skipped', 0)}
        #{summary_row('Unmatched', 1)}
        #{summary_row('Drift warning', 'no')}
      OUTPUT

      expect { reporter.report(result) }.to output(expected_output).to_stdout
    end
  end
end
