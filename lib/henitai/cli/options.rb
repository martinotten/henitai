# frozen_string_literal: true

require "optparse"
require_relative "run_options"

module Henitai
  class CLI
    # Builds the OptionParser instances for the `run` and `clean` commands and
    # parses argv into an options Hash. Help/version options set
    # +@command_halted+ so the caller can skip the rest of the command.
    # Run-only option definitions live in {RunOptions}.
    module Options
      include RunOptions

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
          add_run_flag_options(opts, options)
          add_help_option(opts)
          add_version_option(opts)
        end
      end

      def add_run_flag_options(opts, options)
        add_since_option(opts, options)
        add_integration_option(opts, options)
        add_config_option(opts, options)
        add_operator_option(opts, options)
        add_timeout_multiplier_option(opts, options)
        add_jobs_option(opts, options)
        add_output_option(opts, options)
        add_survivors_from_option(opts, options)
        add_incremental_option(opts, options)
        add_force_option(opts, options)
        add_dry_run_option(opts, options)
        add_fail_on_survivors_option(opts, options)
        add_strict_exit_codes_option(opts, options)
      end

      def build_clean_option_parser(options)
        OptionParser.new do |opts|
          opts.banner = "Usage: henitai clean [options]"
          add_config_option(opts, options)
          add_help_option(opts)
          add_version_option(opts)
        end
      end

      def add_config_option(opts, options)
        opts.on("--config PATH", "Path to .henitai.yml") do |path|
          options[:config] = path
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
