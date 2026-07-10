# frozen_string_literal: true

require "fileutils"
require "json"
require "net/http"
require "open3"
require "uri"
require_relative "unparse_helper"
require_relative "reporter/dashboard_metadata_provider"

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
    # @param history_store [MutantHistoryStore, nil] persistence store the JSON
    #   reporter reads trend data from; supplied by the composition root so the
    #   reporter does not build infrastructure itself.
    def self.run_all(names:, result:, config:, history_store: nil)
      names.each do |name|
        reporter_class(name).new(config:, history_store:).report(result)
      end
    end

    def self.reporter_class(name)
      const_get(name.capitalize)
    rescue NameError
      raise ArgumentError, "Unknown reporter: #{name}. Valid reporters: terminal, json, html, dashboard, github"
    end

    # Base class for all reporters.
    class Base
      # @param history_store [MutantHistoryStore, nil] accepted by every
      #   reporter for a uniform factory signature; only the JSON reporter uses
      #   it. Ignored elsewhere.
      def initialize(config:, history_store: nil)
        @config = config
        @history_store = history_store
      end

      # @param result [Result]
      def report(result)
        raise NotImplementedError, "#{self.class}#report must be implemented"
      end

      private

      attr_reader :config, :history_store

      # Authoritative (full) runs fully replace the canonical report;
      # scoped/partial runs merge into it (CanonicalReportMerger) so
      # findings for files outside this run's scope aren't lost.
      def authoritative?(result)
        return true unless result.respond_to?(:authoritative?)

        result.authoritative?
      end

      # The merge source of truth is always the JSON canonical report, even
      # for the HTML reporter, which embeds the same merged schema.
      def canonical_path
        File.join(config.reports_dir, "mutation-report.json")
      end
    end

    # Terminal reporter.
    class Terminal < Base
      include UnparseHelper

      PROGRESS_GLYPHS = {
        killed: "·",
        survived: "S",
        timeout: "T",
        ignored: "I"
      }.freeze

      def initialize(config:, history_store: nil, color_enabled: !ENV.key?("NO_COLOR"))
        super(config:, history_store:)
        @color_enabled = color_enabled
      end

      def report(result)
        puts report_lines(result)
      end

      def progress(mutant, scenario_result: nil)
        glyph = PROGRESS_GLYPHS[mutant.status]
        return unless glyph

        print(glyph)
        return flush unless should_show_logs?(scenario_result)

        output = scenario_output(scenario_result)
        print("\n")
        print("log: #{scenario_result.log_path}\n")
        print(output) unless output.empty?
        $stdout.flush
      end

      private

      attr_reader :color_enabled

      def report_lines(result)
        lines = summary_lines(result)
        detail_lines = survived_detail_lines(result)
        return lines if detail_lines.empty?

        lines + [""] + detail_lines
      end

      def summary_lines(result)
        if result.respond_to?(:partial_rerun?) && result.partial_rerun?
          partial_summary_lines(result)
        else
          full_summary_lines(result)
        end
      end

      def full_summary_lines(result)
        [
          "Mutation testing summary",
          score_line(result),
          format_row("Killed", count_status(result, :killed)),
          format_row("Survived", count_status(result, :survived)),
          format_row("Timeout", count_status(result, :timeout)),
          format_row("No coverage", count_status(result, :no_coverage)),
          format_row("Duration", format_duration(result.duration)),
          reused_verdicts_line(result),
          executed_only_score_line(result)
        ].compact
      end

      def reused_verdicts_line(result)
        reused = reused_mutants(result)
        return nil if reused.empty?

        format(
          "%<reused>d of %<total>d verdicts reused from history (%<killed>d killed, %<survived>d survived)",
          reused: reused.size,
          total: result.mutants.size,
          killed: reused.count { |mutant| mutant.status == :killed },
          survived: reused.count { |mutant| mutant.status == :survived }
        )
      end

      def reused_mutants(result)
        result.mutants.select { |mutant| mutant.respond_to?(:from_cache?) && mutant.from_cache? }
      end

      # Cached verdicts make the combined MS/MSI partly synthetic; the
      # executed-only pair keeps this run's own signal visible.
      def executed_only_score_line(result)
        return nil unless result.respond_to?(:executed_scoring_summary)

        summary = result.executed_scoring_summary # : Hash[Symbol, untyped]?
        return nil unless summary

        format(
          "Executed-only MS %<score>s | MSI %<indicator>s",
          score: format_percent(summary[:mutation_score]),
          indicator: format_percent(summary[:mutation_score_indicator])
        )
      end

      def partial_summary_lines(result)
        lines = [
          "Partial survivor rerun",
          format_row("Survived", count_status(result, :survived)),
          format_row("Duration", format_duration(result.duration))
        ]
        append_survivor_stats(lines, result)
        lines
      end

      def append_survivor_stats(lines, result)
        return unless result.respond_to?(:survivor_stats)

        stats = result.survivor_stats # : Hash[Symbol, untyped]?
        return unless stats

        lines << format_row("Matched", stats.fetch(:matched))
        lines << format_row("Skipped", stats.fetch(:skipped_count, 0))
        lines << format_row("Unmatched", stats.fetch(:unmatched_count))
        lines << format_row("Drift warning", stats.fetch(:drift_warning) ? "yes" : "no")
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
        format("- %s", display_unparse(mutant.original_node))
      end

      def mutated_line(mutant)
        format("+ %s", display_unparse(mutant.mutated_node))
      end

      # Like safe_unparse but makes invisible characters visible in terminal
      # output. For string literal nodes the inner value is shown via #inspect
      # so that e.g. "" vs " " vs "\n" are unambiguous. Other nodes unparse
      # normally.
      def display_unparse(node)
        if node.respond_to?(:type) && node.respond_to?(:children) && node.type == :str
          node.children.first.inspect
        else
          safe_unparse(node)
        end
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
        return text unless color_enabled

        "\e[#{color}m#{text}\e[0m"
      end

      def should_show_logs?(scenario_result)
        return false unless scenario_result.respond_to?(:failure_tail)

        scenario_result.should_show_logs?(all_logs: config.all_logs)
      end

      def scenario_output(scenario_result)
        scenario_result.failure_tail(all_logs: config.all_logs)
      end

      def flush
        $stdout.flush
      end
    end

    # JSON reporter.
    class Json < Base
      def report(result)
        schema = result.to_stryker_schema
        write_canonical(schema, authoritative: authoritative?(result))
        write_session_snapshot(schema)
        write_activation_recipes(result)
        write_history_report
      end

      private

      def write_canonical(schema, authoritative:)
        CanonicalReportWriter.write(schema, path: canonical_path, authoritative:)
      end

      def write_session_snapshot(schema)
        session_id = schema[:sessionId]
        return unless session_id

        path = session_snapshot_path(session_id)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.pretty_generate(schema))
      end

      def write_activation_recipes(result)
        session_id = result.session_id if result.respond_to?(:session_id)
        return unless session_id

        survived = survived_mutants_for(result)
        return if survived.empty?

        recipes = SurvivorActivationCache.compute(survived)
        return if recipes.empty?

        SurvivorActivationCache.write(session_recipe_path(session_id), recipes)
      end

      def survived_mutants_for(result)
        return [] unless result.respond_to?(:mutants)

        result.mutants.select(&:survived?)
      end

      def session_snapshot_path(session_id)
        File.join(config.reports_dir, "sessions", session_id, "mutation-report.json")
      end

      def session_recipe_path(session_id)
        File.join(config.reports_dir, "sessions", session_id, SurvivorActivationCache::FILENAME)
      end

      def write_history_report
        store = history_store || default_history_store
        return unless File.exist?(store.path)

        FileUtils.mkdir_p(File.dirname(history_report_path))
        File.write(history_report_path, JSON.pretty_generate(store.trend_report))
      end

      def default_history_store
        MutantHistoryStore.new(
          path: File.join(config.reports_dir, Henitai::HISTORY_STORE_FILENAME)
        )
      end

      def history_report_path
        File.join(config.reports_dir, "mutation-history.json")
      end
    end

    # HTML reporter.
    class Html < Base
      def report(result)
        report_schema(schema_for(result))
      end

      def report_schema(schema)
        FileUtils.mkdir_p(File.dirname(report_path))
        File.write(report_path, html_document(schema))
      end

      private

      def report_path
        File.join(config.reports_dir, "mutation-report.html")
      end

      def html_document(schema)
        <<~HTML
          <!DOCTYPE html>
          <html lang="en">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <title>Henitai mutation report</title>
            </head>
            <body>
              <mutation-test-report-app titlePostfix="Henitai"></mutation-test-report-app>
              <script src="https://www.unpkg.com/mutation-testing-elements"></script>
              <script type="application/json" id="henitai-report-data">#{escaped_report_json(schema)}</script>
              <script>
                const report = JSON.parse(
                  document.getElementById("henitai-report-data").textContent
                );
                document.querySelector("mutation-test-report-app").report = report;
              </script>
            </body>
          </html>
        HTML
      end

      def schema_for(result)
        schema = result.to_stryker_schema
        return schema if authoritative?(result)

        CanonicalReportMerger.merge(schema, canonical_path, prune_missing: true)
      end

      def escaped_report_json(schema)
        JSON.pretty_generate(schema)
            .gsub("&", "\\u0026")
            .gsub("<", "\\u003c")
            .gsub(">", "\\u003e")
      end
    end

    # Dry-run listing: prints the post-filter mutant set (Gates 0–3) without
    # any execution results. Used internally by the runner for `--dry-run`;
    # not part of the `reporters:` configuration surface.
    class DryRun < Base
      def initialize(config:, history_store: nil, io: $stdout)
        super(config:, history_store:)
        @io = io
      end

      def report(result)
        io.puts(listing_lines(result.mutants))
      end

      private

      attr_reader :io

      def listing_lines(mutants)
        header = ["Dry run: #{mutants.size} mutants (no mutants executed)"]
        return header + ["", summary_line(mutants)] if mutants.empty?

        header + grouped_lines(mutants) + ["", summary_line(mutants)]
      end

      def grouped_lines(mutants)
        mutants.group_by { |mutant| subject_label(mutant) }.flat_map do |label, subject_mutants|
          ["", label] + subject_mutants.map { |mutant| mutant_line(mutant) }
        end
      end

      def subject_label(mutant)
        subject = mutant.subject
        return subject.expression if subject.respond_to?(:expression) && subject.expression

        mutant.location.fetch(:file, "(unknown subject)")
      end

      def mutant_line(mutant)
        line = format(
          "  %<operator>s — %<description>s  %<file>s:%<line>d  [%<status>s]",
          operator: mutant.operator,
          description: mutant.description,
          file: mutant.location.fetch(:file),
          line: mutant.location.fetch(:start_line),
          status: mutant.status
        )
        reason = ignore_reason_for(mutant)
        reason ? "#{line} #{reason}" : line
      end

      def ignore_reason_for(mutant)
        return nil unless mutant.respond_to?(:ignore_reason)

        reason = mutant.ignore_reason
        reason ? "(#{reason})" : nil
      end

      def summary_line(mutants)
        counts = mutants.group_by(&:status).transform_values(&:size)
        summary = counts.map { |status, count| "#{status} #{count}" }.join(" | ")
        "Summary: #{summary.empty? ? 'no mutants' : summary}"
      end
    end

    # GitHub Actions annotation reporter. Prints one `::warning` workflow
    # command per survived mutant so survivors show up inline on the PR diff.
    # Killed/ignored/no-coverage/timeout mutants stay silent.
    class Github < Base
      def initialize(config:, history_store: nil, io: $stdout)
        super(config:, history_store:)
        @io = io
      end

      def report(result)
        result.mutants.select(&:survived?).each do |mutant|
          io.puts(annotation_line(mutant))
        end
      end

      private

      attr_reader :io

      def annotation_line(mutant)
        format(
          "::warning file=%<file>s,line=%<line>d::%<message>s",
          file: relative_path(mutant.location.fetch(:file)),
          line: mutant.location.fetch(:start_line),
          message: escape_message("Survived mutant: #{mutant.operator} — #{mutant.description}")
        )
      end

      def relative_path(file)
        pathname = Pathname.new(file)
        return file unless pathname.absolute?

        pathname.relative_path_from(Dir.pwd).to_s
      end

      # GitHub workflow-command message payload escaping: only `%`, LF and CR
      # are significant; everything else is parsed literally.
      def escape_message(message)
        message.gsub("%", "%25").gsub("\n", "%0A").gsub("\r", "%0D")
      end
    end

    # Dashboard reporter. Delegates project/version/api-key resolution to
    # {DashboardMetadataProvider} so it never touches real ENV or git itself.
    class Dashboard < Base
      DEFAULT_BASE_URL = "https://dashboard.stryker-mutator.io"
      HTTP_TIMEOUT_SECONDS = 30

      def initialize(config:, history_store: nil, metadata_provider: nil)
        super(config:, history_store:)
        @metadata_provider = metadata_provider || DashboardMetadataProvider.new(dashboard_config: config.dashboard)
      end

      def report(result)
        return unless ready?

        uri = dashboard_uri
        request = build_request(result, uri)
        send_request(uri, request)
      end

      class << self
        def project_from_git_url(url)
          DashboardMetadataProvider.project_from_git_url(url)
        end
      end

      private

      attr_reader :metadata_provider

      def project = metadata_provider.project
      def version = metadata_provider.version
      def api_key = metadata_provider.api_key

      def ready?
        !project.nil? && !version.nil? && !api_key.nil?
      end

      def build_request(result, uri)
        request = Net::HTTP::Put.new(uri.request_uri, request_headers)
        request.body = JSON.generate(result.to_stryker_schema)
        request
      end

      def request_headers
        {
          "Content-Type" => "application/json",
          "X-Api-Key" => api_key.to_s
        }
      end

      def send_request(uri, request)
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
          http.open_timeout = HTTP_TIMEOUT_SECONDS
          http.read_timeout = HTTP_TIMEOUT_SECONDS
          http.request(request)
        end
      rescue StandardError => e
        warn("Dashboard reporter upload failed: #{e.message}")
        nil
      end

      def dashboard_uri
        uri = URI.parse(base_url)
        # @type var segments: Array[String]
        base_path = uri.path.to_s.chomp("/").delete_prefix("/")
        segments = []
        segments << base_path unless base_path.empty?
        segments += ["api", "reports", project_path, encoded_version]
        uri.path = "/#{segments.join('/')}"
        uri
      rescue URI::InvalidURIError
        URI.parse(DEFAULT_BASE_URL)
      end

      def base_url
        config.dashboard[:base_url] || DEFAULT_BASE_URL
      end

      def project_path
        project.to_s.split("/").map { |segment| URI.encode_www_form_component(segment) }.join("/")
      end

      def encoded_version
        URI.encode_www_form_component(version.to_s)
      end
    end
  end
end
