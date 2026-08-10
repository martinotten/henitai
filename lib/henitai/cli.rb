# frozen_string_literal: true

require_relative "cli/command_support"
require_relative "cli/options"
require_relative "cli/run_command"
require_relative "cli/clean_command"
require_relative "cli/init_command"
require_relative "cli/operator_command"

module Henitai
  # Command-line interface entry point.
  #
  # Usage:
  #   henitai run [options] [SUBJECT_PATTERN...]
  #
  # Options:
  #   --since GIT_REF   Only mutate subjects changed since GIT_REF
  #   --use INTEGRATION Override integration from config (e.g. rspec)
  #   --config PATH     Path to .henitai.yml (default: .henitai.yml)
  #   --operators SET   Operator set: light (default) | full | hard
  #   --jobs N          Number of parallel workers (default: 1)
  #   --all-logs        Print all captured child logs
  #   -h, --help        Show this help message
  #   -v, --version     Show version
  #
  # Argument parsing and command dispatch live here; the per-command behaviour
  # lives in the mixed-in command modules under +lib/henitai/cli/+.
  class CLI
    include CommandSupport
    include Options
    include RunCommand
    include CleanCommand
    include InitCommand
    include OperatorCommand

    REPORT_CLEANUP_PATHS = [
      %w[coverage .resultset.json],
      %w[coverage .last_run.json],
      ["henitai_per_test.json"],
      [CoverageBootstrapper::DEPENDENCY_MANIFEST_FILE]
    ].freeze

    # Whole directories of per-mutant scratch artifacts, removed recursively.
    # `mutation-logs` accumulates one stdout/stderr/combined log trio per
    # mutant (and baseline) and `mutation-coverage` one dir per mutant, so both
    # grow to GBs on a large run; deleting the tree is the only way to reclaim
    # it (rm_f cannot remove a directory).
    REPORT_CLEANUP_DIRS = [
      %w[mutation-logs],
      %w[mutation-coverage]
    ].freeze

    def self.start(argv)
      new(argv).run
    end

    def initialize(argv)
      @argv = argv.dup
    end

    def run
      command = @argv.shift
      case command
      when "run"     then run_command
      when "clean"   then clean_command
      when "version" then puts Henitai::VERSION
      when "init"    then init_command
      when "operator" then operator_command
      when nil, "-h", "--help" then puts help_text
      else
        warn "Unknown command: #{command}"
        warn help_text
        exit 1
      end
    end

    private

    def help_text
      <<~HELP
        Hen'i-tai 変異体 #{Henitai::VERSION} — Ruby Mutation Testing

        Usage:
          henitai run [options] [SUBJECT_PATTERN...]
          henitai clean [options]
          henitai version
          henitai init [PATH]
          henitai operator list

        Examples:
          bundle exec henitai run
          bundle exec henitai run --since origin/main
          bundle exec henitai run 'Foo::Bar#my_method'
          bundle exec henitai run 'MyNamespace*' --operators full
          bundle exec henitai run --survivors-from reports/mutation-report.json
          bundle exec henitai clean
          bundle exec henitai init
          bundle exec henitai operator list

        Run `henitai run --help` for full option list.
      HELP
    end
  end
end
