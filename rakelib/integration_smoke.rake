# frozen_string_literal: true

require "bundler"
require "json"
require "open3"

#
# Helpers for running the committed framework smoke projects through rake.
module IntegrationSmoke
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
      return if status.exitstatus == 1 && survivor_count.positive?

      details = [stdout, stderr].reject(&:empty?).join("\n")
      raise "Expected surviving mutants for #{name}\n#{details}"
    end

    def announce_success
      puts format(
        "smoke:%<name>s ok (%<count>d surviving mutants in %<report>s)",
        name:,
        count: survivor_count,
        report: report_path
      )
    end

    def survivor_count
      report.fetch("files").values.sum do |file|
        file.fetch("mutants").count { |mutant| mutant.fetch("status") == "Survived" }
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

    desc "Run the Minitest integration smoke project"
    task :minitest do
      IntegrationSmoke::Project.new("minitest", root: IntegrationSmoke::PROJECT_ROOTS[:minitest]).run!
    end

    desc "Run both integration smoke projects"
    task all: %i[rspec minitest]
  end
end
