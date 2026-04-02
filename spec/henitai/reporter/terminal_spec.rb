# frozen_string_literal: true

require "fileutils"
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
    Struct.new(:mutants, :scoring_summary, :duration).new(
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

  def with_no_color
    original = ENV.fetch("NO_COLOR", nil)
    ENV["NO_COLOR"] = "1"
    yield
  ensure
    if original.nil?
      ENV.delete("NO_COLOR")
    else
      ENV["NO_COLOR"] = original
    end
  end

  def with_color
    original = ENV.fetch("NO_COLOR", nil)
    ENV.delete("NO_COLOR")
    yield
  ensure
    if original.nil?
      ENV.delete("NO_COLOR")
    else
      ENV["NO_COLOR"] = original
    end
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
    allow(Unparser).to receive(:unparse).with(mutant.original_node).and_raise(StandardError, "boom")
    allow(Unparser).to receive(:unparse).with(mutant.mutated_node).and_raise(StandardError, "boom")
    result = build_result(
      mutants: [mutant],
      scoring_summary: survived_detail_scoring_summary,
      duration: 12.34
    )

    expect { reporter.report(result) }.to output(/dstr/).to_stdout
  end

  it "prints a summary table with score, counts, and duration" do
    reporter = described_class.new(config: build_config)
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

    with_color do
      expect { reporter.report(result) }.to output(expected_output).to_stdout
    end
  end

  it "colors the score line green when the score meets the high threshold" do
    reporter = described_class.new(config: build_config)
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

    with_color do
      expect { reporter.report(result) }.to output(expected_output).to_stdout
    end
  end

  it "colors the score line yellow when the score meets the low threshold" do
    reporter = described_class.new(config: build_config)
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

    with_color do
      expect { reporter.report(result) }.to output(expected_output).to_stdout
    end
  end

  it "colors the score line red when the score is below the low threshold" do
    reporter = described_class.new(config: build_config)
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

    with_color do
      expect { reporter.report(result) }.to output(expected_output).to_stdout
    end
  end

  it "does not emit ANSI colors when NO_COLOR is set" do
    reporter = described_class.new(config: build_config)
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

    with_no_color do
      expect { reporter.report(result) }.to output(expected_output).to_stdout
    end
  end

  it "prints n/a when the scoring summary does not include live mutants" do
    reporter = described_class.new(config: build_config)
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

    with_color do
      expect { reporter.report(result) }.to output(expected_output).to_stdout
    end
  end

  it "prints survived mutant details after the summary block" do
    reporter = described_class.new(config: build_config)
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

    with_color do
      expect { reporter.report(result) }.to output(expected_output).to_stdout
    end
  end

  it "uses default thresholds when config.thresholds is nil" do
    config = Struct.new(:thresholds, :all_logs).new(nil, false)
    reporter = described_class.new(config:)
    # 75 falls between default low=60 and high=80 → yellow "33"
    expect(reporter.send(:score_color, 75)).to eq("33")
  end

  it "delegates flush to stdout" do
    reporter = described_class.new(config: build_config)
    allow($stdout).to receive(:flush)
    reporter.send(:flush)
    expect($stdout).to have_received(:flush)
  end
end
