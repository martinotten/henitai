# frozen_string_literal: true

require "json"
require "unparser"

module Henitai
  # Namespace for result reporters.
  #
  # Each reporter receives a Result object and writes output in its specific
  # format. Reporters are selected via `reporters:` in .henitai.yml.
  #
  # Built-in reporters:
  #   terminal  — coloured summary table to STDOUT
  #   json      — mutation-testing-report-schema JSON file
  #   html      — self-contained HTML using mutation-testing-elements web component
  #   dashboard — POST to Stryker Dashboard REST API
  module Reporter
    # @param names  [Array<String>] reporter names from configuration
    # @param result [Result]
    # @param config [Configuration]
    def self.run_all(names:, result:, config:)
      names.each do |name|
        reporter_class(name).new(config:).report(result)
      end
    end

    def self.reporter_class(name)
      const_get(name.capitalize)
    rescue NameError
      raise ArgumentError, "Unknown reporter: #{name}. Valid reporters: terminal, json, html, dashboard"
    end

    # Base class for all reporters.
    class Base
      def initialize(config:)
        @config = config
      end

      # @param result [Result]
      def report(result)
        raise NotImplementedError, "#{self.class}#report must be implemented"
      end

      private

      attr_reader :config
    end

    # Terminal reporter.
    class Terminal < Base
      PROGRESS_GLYPHS = {
        killed: "·",
        survived: "S",
        timeout: "T",
        ignored: "I"
      }.freeze

      def report(result)
        puts report_lines(result)
      end

      def progress(mutant)
        glyph = PROGRESS_GLYPHS[mutant.status]
        return unless glyph

        print(glyph)
        $stdout.flush
      end

      private

      def report_lines(result)
        lines = summary_lines(result)
        detail_lines = survived_detail_lines(result)
        return lines if detail_lines.empty?

        lines + [""] + detail_lines
      end

      def summary_lines(result)
        [
          "Mutation testing summary",
          score_line(result),
          format_row("Killed", count_status(result, :killed)),
          format_row("Survived", count_status(result, :survived)),
          format_row("Timeout", count_status(result, :timeout)),
          format_row("No coverage", count_status(result, :no_coverage)),
          format_row("Duration", format_duration(result.duration))
        ]
      end

      def survived_detail_lines(result)
        survivors = result.mutants.select(&:survived?)
        return [] if survivors.empty?

        ["Survived mutants"] + survivors.flat_map { |mutant| survived_mutant_lines(mutant) }
      end

      def survived_mutant_lines(mutant)
        [
          survived_mutant_header(mutant),
          original_line(mutant),
          mutated_line(mutant)
        ]
      end

      def survived_mutant_header(mutant)
        format(
          "%<file>s:%<line>d %<operator>s",
          file: mutant.location.fetch(:file),
          line: mutant.location.fetch(:start_line),
          operator: mutant.operator
        )
      end

      def original_line(mutant)
        format("- %s", Unparser.unparse(mutant.original_node))
      end

      def mutated_line(mutant)
        format("+ %s", Unparser.unparse(mutant.mutated_node))
      end

      def score_line(result)
        summary = result.scoring_summary
        line = [
          format("MS %s", format_percent(summary[:mutation_score])),
          format("MSI %s", format_percent(summary[:mutation_score_indicator])),
          format(
            "Equivalence uncertainty %s",
            summary[:equivalence_uncertainty] || "n/a"
          )
        ].join(" | ")
        color = score_color(summary[:mutation_score])
        color ? colorize(line, color) : line
      end

      def format_row(label, value)
        format("%<label>-12s %<value>s", label:, value:)
      end

      def count_status(result, status)
        result.mutants.count { |mutant| mutant.status == status }
      end

      def format_duration(duration)
        format("%.2fs", duration)
      end

      def format_percent(value)
        value.nil? ? "n/a" : format("%.2f%%", value)
      end

      def score_color(score)
        return nil if score.nil?

        thresholds = config.thresholds || {}
        high = thresholds.fetch(:high, 80)
        low = thresholds.fetch(:low, 60)

        return "32" if score >= high
        return "33" if score >= low

        "31"
      end

      def colorize(text, color)
        "\e[#{color}m#{text}\e[0m"
      end
    end

    # JSON reporter.
    class Json < Base
      def report(result)
        ensure_report_directory
        File.write(report_path, result.to_stryker_schema.to_json)
      end

      private

      def report_path
        File.join(config.reports_dir, "mutation-report.json")
      end

      def ensure_report_directory
        mkdir_p(File.dirname(report_path))
      end

      def mkdir_p(path)
        return if Dir.exist?(path)

        parent = File.dirname(path)
        mkdir_p(parent) unless parent == path
        Dir.mkdir(path)
      end
    end

    # HTML reporter.
    class Html < Base
      def report(result)
        raise NotImplementedError
      end
    end

    # Dashboard reporter.
    class Dashboard < Base
      def report(result)
        raise NotImplementedError
      end
    end
  end
end
