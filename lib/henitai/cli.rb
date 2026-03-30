# frozen_string_literal: true

require "optparse"

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
  #   --operators SET   Operator set: light (default) | full
  #   --jobs N          Number of parallel workers (default: CPU count)
  #   -h, --help        Show this help message
  #   -v, --version     Show version
  class CLI
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
      when "version" then puts Henitai::VERSION
      when nil, "-h", "--help" then puts help_text
      else
        warn "Unknown command: #{command}"
        warn help_text
        exit 1
      end
    end

    private

    def run_command
      options = parse_run_options
      config = Configuration.load(
        path: options.fetch(:config, Configuration::CONFIG_FILE),
        overrides: configuration_overrides(options)
      )
      subjects = @argv.empty? ? nil : @argv.map { |expr| Subject.parse(expr) }

      runner = Runner.new(
        config:,
        subjects:,
        since: options[:since]
      )

      result = runner.run

      exit(result.mutation_score.to_i >= config.thresholds[:low] ? 0 : 1)
    end

    def parse_run_options
      options = {}
      build_run_option_parser(options).parse!(@argv)
      options
    end

    def configuration_overrides(options)
      deep_compact(
        {
          integration: options[:integration],
          mutation: {
            operators: options[:operators],
            timeout: options[:timeout]
          },
          jobs: options[:jobs]
        }
      )
    end

    def deep_compact(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested_value), result|
          compacted = deep_compact(nested_value)
          result[key] = compacted unless compacted.nil?
        end
      when Array
        value.map { |item| deep_compact(item) }.compact
      else
        value
      end
    end

    def build_run_option_parser(options)
      OptionParser.new do |opts|
        opts.banner = "Usage: henitai run [options] [SUBJECT_PATTERN...]"
        add_since_option(opts, options)
        add_integration_option(opts, options)
        add_config_option(opts, options)
        add_operator_option(opts, options)
        add_jobs_option(opts, options)
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
      opts.on("--jobs N", Integer, "Number of parallel workers") do |n|
        options[:jobs] = n
      end
    end

    def add_help_option(opts)
      opts.on("-h", "--help", "Show this help") do
        puts opts
        exit
      end
    end

    def add_version_option(opts)
      opts.on("-v", "--version", "Show version") do
        puts Henitai::VERSION
        exit
      end
    end

    def help_text
      <<~HELP
        Hen'i-tai 変異体 #{Henitai::VERSION} — Ruby 4 Mutation Testing

        Usage:
          henitai run [options] [SUBJECT_PATTERN...]
          henitai version

        Examples:
          bundle exec henitai run
          bundle exec henitai run --since origin/main
          bundle exec henitai run 'Foo::Bar#my_method'
          bundle exec henitai run 'MyNamespace*' --operators full

        Run `henitai run --help` for full option list.
      HELP
    end
  end
end
