# frozen_string_literal: true

require "optparse"

module Henitai
  class CLI
    # Builds the OptionParser instances for the `run` and `clean` commands and
    # parses argv into an options Hash. Help/version options set
    # +@command_halted+ so the caller can skip the rest of the command.
    module Options
      private

      def parse_run_options
        options = {}
        build_run_option_parser(options).parse!(@argv)
        options
      end

      def parse_clean_options
        options = {}
        build_clean_option_parser(options).parse!(@argv)
        options
      end

      def build_run_option_parser(options)
        OptionParser.new do |opts|
          opts.banner = "Usage: henitai run [options] [SUBJECT_PATTERN...]"
          add_since_option(opts, options)
          add_integration_option(opts, options)
          add_config_option(opts, options)
          add_operator_option(opts, options)
          add_jobs_option(opts, options)
          add_output_option(opts, options)
          add_survivors_from_option(opts, options)
          add_fail_on_survivors_option(opts, options)
          add_help_option(opts)
          add_version_option(opts)
        end
      end

      def build_clean_option_parser(options)
        OptionParser.new do |opts|
          opts.banner = "Usage: henitai clean [options]"
          add_config_option(opts, options)
          add_help_option(opts)
          add_version_option(opts)
        end
      end

      def add_since_option(opts, options)
        opts.on("--since GIT_REF", "Only mutate subjects changed since GIT_REF") do |ref|
          options[:since] = ref
        end
      end

      def add_integration_option(opts, options)
        opts.on("--use INTEGRATION", "Test framework integration (rspec)") do |name|
          options[:integration] = name
        end
      end

      def add_config_option(opts, options)
        opts.on("--config PATH", "Path to .henitai.yml") do |path|
          options[:config] = path
        end
      end

      def add_operator_option(opts, options)
        opts.on("--operators SET", "Operator set: light | full") do |set|
          options[:operators] = set
        end
      end

      def add_jobs_option(opts, options)
        opts.on("--jobs N", Integer, "Number of parallel workers (default: 1)") do |n|
          options[:jobs] = n
        end
      end

      def add_output_option(opts, options)
        opts.on("--all-logs", "--verbose", "Print all captured child logs") do
          options[:all_logs] = true
        end
      end

      def add_survivors_from_option(opts, options)
        opts.on(
          "--survivors-from PATH",
          "Re-run only survivors from a prior report " \
          "(partial rerun; threshold checks are skipped; dirty worktrees are included)"
        ) do |path|
          options[:survivors_from] = path
        end
      end

      def add_fail_on_survivors_option(opts, options)
        opts.on(
          "--fail-on-survivors",
          "Exit 1 for partial reruns when any survivors remain (otherwise exits 0)"
        ) do
          options[:fail_on_survivors] = true
        end
      end

      def add_help_option(opts)
        opts.on("-h", "--help", "Show this help") do
          puts opts
          @command_halted = true
        end
      end

      def add_version_option(opts)
        opts.on("-v", "--version", "Show version") do
          puts Henitai::VERSION
          @command_halted = true
        end
      end
    end
  end
end
