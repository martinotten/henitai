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
      options  = parse_run_options
      config   = Configuration.load(path: options.fetch(:config, Configuration::CONFIG_FILE))
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
      parser  = OptionParser.new do |opts|
        opts.banner = "Usage: henitai run [options] [SUBJECT_PATTERN...]"

        opts.on("--since GIT_REF", "Only mutate subjects changed since GIT_REF") do |ref|
          options[:since] = ref
        end

        opts.on("--use INTEGRATION", "Test framework integration (rspec)") do |name|
          options[:integration] = name
        end

        opts.on("--config PATH", "Path to .henitai.yml") do |path|
          options[:config] = path
        end

        opts.on("--operators SET", "Operator set: light | full") do |set|
          options[:operators] = set
        end

        opts.on("--jobs N", Integer, "Number of parallel workers") do |n|
          options[:jobs] = n
        end

        opts.on("-h", "--help", "Show this help") { puts opts; exit }
        opts.on("-v", "--version", "Show version") { puts Henitai::VERSION; exit }
      end
      parser.parse!(@argv)
      options
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
