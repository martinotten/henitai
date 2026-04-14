# frozen_string_literal: true

require "fileutils"
require "json"
require "net/http"
require "open3"
require "uri"
require_relative "unparse_helper"

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
      include UnparseHelper

      PROGRESS_GLYPHS = {
        killed: "·",
        survived: "S",
        timeout: "T",
        ignored: "I"
      }.freeze

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
        return text if ENV.key?("NO_COLOR")

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
        FileUtils.mkdir_p(File.dirname(report_path))
        File.write(report_path, JSON.pretty_generate(result.to_stryker_schema))
        write_history_report
      end

      private

      def report_path
        File.join(config.reports_dir, "mutation-report.json")
      end

      def write_history_report
        path = File.join(config.reports_dir, Henitai::HISTORY_STORE_FILENAME)
        history_store = MutantHistoryStore.new(path:)
        return unless File.exist?(path)

        FileUtils.mkdir_p(File.dirname(history_report_path))
        File.write(history_report_path, JSON.pretty_generate(history_store.trend_report))
      end

      def history_report_path
        File.join(config.reports_dir, "mutation-history.json")
      end
    end

    # HTML reporter.
    class Html < Base
      def report(result)
        FileUtils.mkdir_p(File.dirname(report_path))
        File.write(report_path, html_document(result))
      end

      private

      def report_path
        File.join(config.reports_dir, "mutation-report.html")
      end

      def html_document(result)
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
              <script type="application/json" id="henitai-report-data">#{escaped_report_json(result)}</script>
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

      def escaped_report_json(result)
        JSON.pretty_generate(result.to_stryker_schema)
            .gsub("&", "\\u0026")
            .gsub("<", "\\u003c")
            .gsub(">", "\\u003e")
      end
    end

    # Dashboard reporter.
    class Dashboard < Base
      DEFAULT_BASE_URL = "https://dashboard.stryker-mutator.io"
      HTTP_TIMEOUT_SECONDS = 30

      def report(result)
        return unless ready?

        uri = dashboard_uri
        request = build_request(result, uri)
        send_request(uri, request)
      end

      private

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
        base_path = uri.path.to_s.chomp("/")
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

      def project
        @project ||= config.dashboard[:project] || project_from_git_remote
      end

      def version
        @version ||= env_version || git_branch_name
      end

      def env_version
        ref_name = ENV.fetch("GITHUB_REF_NAME", nil)
        return ref_name unless blank?(ref_name)

        ref = ENV.fetch("GITHUB_REF", nil)
        return ref_without_prefix(ref) unless ref.nil? || blank?(ref)

        ENV.fetch("GITHUB_SHA", nil)
      end

      def ref_without_prefix(ref)
        return nil if blank?(ref)

        ref.to_s.sub(%r{^refs/(heads|tags|pull)/}, "")
      end

      def project_from_git_remote
        self.class.project_from_git_url(git_remote_url)
      end

      def api_key
        ENV.fetch("STRYKER_DASHBOARD_API_KEY", nil)
      end

      def project_path
        project.to_s.split("/").map { |segment| URI.encode_www_form_component(segment) }.join("/")
      end

      def encoded_version
        URI.encode_www_form_component(version.to_s)
      end

      def blank?(value)
        value.nil? || value.strip.empty?
      end

      def git_remote_url
        stdout, status = Open3.capture2("git", "remote", "get-url", "origin")
        return stdout.strip if status.success?

        nil
      rescue Errno::ENOENT
        nil
      end

      def git_branch_name
        stdout, status = Open3.capture2("git", "rev-parse", "--abbrev-ref", "HEAD")
        return stdout.strip if status.success? && !stdout.strip.empty?

        nil
      rescue Errno::ENOENT
        nil
      end

      class << self
        def project_from_git_url(url)
          normalized = normalize_git_url(url)
          return nil if normalized.nil?

          return project_from_uri_url(normalized) if normalized.include?("://")
          return project_from_ssh_url(normalized) if normalized.include?("@")

          normalized
        rescue URI::InvalidURIError
          nil
        end

        def normalize_git_url(url)
          return nil if url.nil? || url.strip.empty?

          url.strip.sub(/\.git\z/, "")
        end

        def project_from_uri_url(normalized)
          uri = URI.parse(normalized)
          path = uri.path.to_s.sub(%r{^/}, "")
          [uri.host, path].compact.reject(&:empty?).join("/")
        end

        def project_from_ssh_url(normalized)
          _, host_and_path = normalized.split("@", 2)
          return nil if host_and_path.nil?

          host, path = host_and_path.split(":", 2)
          return nil unless host && path

          "#{host}/#{path}"
        end
      end
    end
  end
end
