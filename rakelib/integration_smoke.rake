# frozen_string_literal: true

require "bundler"
require "json"
require "open3"
require "timeout"
require_relative "../lib/henitai"

#
# Helpers for running the committed framework smoke projects through rake.
module IntegrationSmoke
  # Runs the repo's own RSpec baseline suite subprocess against one real spec
  # file to catch regressions in the dogfood execution path quickly.
  class DogfoodRspec
    TIMEOUT_SECONDS = 15

    def initialize(root:)
      @root = root
    end

    def run!
      stdout, stderr, status = Timeout.timeout(TIMEOUT_SECONDS) do
        capture(*command)
      end

      return announce_success if child_succeeded?(stdout, status)

      details = [stdout, stderr].reject(&:empty?).join("\n")
      raise "Dogfood RSpec smoke failed\n#{details}"
    rescue Timeout::Error
      raise "Dogfood RSpec smoke timed out after #{TIMEOUT_SECONDS}s"
    end

    private

    attr_reader :root

    def command
      [
        "bundle", "exec", "ruby",
        "-r", "henitai/rspec_coverage_formatter",
        "-e", Henitai::Integration::Rspec.new.send(:rspec_suite_runner_script),
        "spec/henitai/cli_spec.rb"
      ]
    end

    def announce_success
      puts "smoke:dogfood_rspec ok (baseline suite script completed on spec/henitai/cli_spec.rb)"
    end

    def child_succeeded?(stdout, status)
      status.success? || stdout.match?(/\b0 failures\b/)
    end

    def capture(*command)
      Open3.capture3(*command, chdir: root)
    end
  end

  # Runs one committed smoke project and asserts that Henitai reports
  # at least one surviving mutant for it.
  class Project
    def initialize(name, root:)
      @name = name
      @root = root
    end

    def run!
      Bundler.with_unbundled_env do
        ensure_bundle!
        stdout, stderr, status = capture("bundle", "exec", "henitai", "run")
        verify_run!(stdout, stderr, status)
        announce_success
      end
    end

    private

    attr_reader :name, :root

    def ensure_bundle!
      _stdout, _stderr, status = capture("bundle", "check")
      return if status.success?

      stdout, stderr, install_status = capture("bundle", "install")
      return if install_status.success?

      raise [stdout, stderr].reject(&:empty?).join("\n")
    end

    def verify_run!(stdout, stderr, status)
      unless status.exitstatus == 1 && survivor_count.positive? && ignored_count.positive? && killed_count.positive?
        details = [stdout, stderr].reject(&:empty?).join("\n")
        raise "Expected surviving, killed, and ignored mutants for #{name}\n#{details}"
      end

      verify_worker_slot!
      verify_per_operator_disable!
    end

    # Proves per-operator `henitai:disable` selectivity end-to-end: on the
    # `cheer` line, ArithmeticOperator must be Ignored with the directive's
    # reason while at least one sibling operator's mutant still executed.
    def verify_per_operator_disable!
      ignored = per_operator_ignored_mutants
      raise "Expected an Ignored ArithmeticOperator with statusReason for #{name}" if ignored.empty?

      lines = ignored.map { |m| m.dig("location", "start", "line") }
      raise "Expected a live sibling mutant on the per-operator disable line for #{name}" unless
        live_sibling_on?(lines)
    end

    def per_operator_ignored_mutants
      greeting_mutants.select do |m|
        m.fetch("mutatorName").to_s == "ArithmeticOperator" &&
          m.fetch("status") == "Ignored" &&
          m["statusReason"] == "smoke per-operator"
      end
    end

    def live_sibling_on?(lines)
      greeting_mutants.any? do |m|
        lines.include?(m.dig("location", "start", "line")) && m.fetch("status") != "Ignored"
      end
    end

    def greeting_mutants
      @greeting_mutants ||= report.fetch("files")
                                  .select { |path, _| path.end_with?("greeting.rb") }
                                  .values.flat_map { |file| file.fetch("mutants") }
    end

    # Proves HENITAI_WORKER_SLOT survives the real fork + integration
    # boundary: the fixture suite writes the value it saw to an artifact.
    def verify_worker_slot!
      path = File.join(root, "reports", "worker-slot.txt")
      raise "Expected worker-slot artifact for #{name} at #{path}" unless File.exist?(path)

      value = File.read(path)
      raise "Invalid worker slot #{value.inspect} for #{name}" unless value.match?(/\A\d+\z/)
    end

    def announce_success
      puts format(
        "smoke:%<name>s ok (%<killed>d killed, %<survived>d surviving, %<ignored>d ignored mutants in %<report>s)",
        name:,
        killed: killed_count,
        survived: survivor_count,
        ignored: ignored_count,
        report: report_path
      )
    end

    def killed_count
      status_count("Killed")
    end

    def survivor_count
      status_count("Survived")
    end

    def ignored_count
      status_count("Ignored")
    end

    def status_count(status)
      report.fetch("files").values.sum do |file|
        file.fetch("mutants").count { |mutant| mutant.fetch("status") == status }
      end
    end

    def report_path
      File.join(root, "reports", "mutation-report.json")
    end

    def report
      JSON.parse(File.read(report_path))
    end

    def capture(*command)
      Open3.capture3(*command, chdir: root)
    end
  end

  unless const_defined?(:PROJECT_ROOTS, false)
    PROJECT_ROOTS = {
      rspec: File.expand_path(File.join(__dir__, "..", "spec", "fixtures", "integration_smoke", "rspec")),
      minitest: File.expand_path(File.join(__dir__, "..", "spec", "fixtures", "integration_smoke", "minitest"))
    }.freeze
  end
end

namespace :smoke do
  namespace :integration do
    desc "Run the RSpec integration smoke project"
    task :rspec do
      IntegrationSmoke::Project.new("rspec", root: IntegrationSmoke::PROJECT_ROOTS[:rspec]).run!
    end

    desc "Run the repo-level dogfood RSpec baseline smoke path"
    task :dogfood_rspec do
      IntegrationSmoke::DogfoodRspec.new(
        root: File.expand_path(File.join(__dir__, ".."))
      ).run!
    end

    desc "Run the Minitest integration smoke project"
    task :minitest do
      IntegrationSmoke::Project.new("minitest", root: IntegrationSmoke::PROJECT_ROOTS[:minitest]).run!
    end

    desc "Run both integration smoke projects"
    task all: %i[rspec dogfood_rspec minitest]
  end
end
