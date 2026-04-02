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
  #   --all-logs        Print all captured child logs
  #   -h, --help        Show this help message
  #   -v, --version     Show version
  # rubocop:disable Metrics/ClassLength
  class CLI
    INIT_TEMPLATE_LINES = [
      "# yaml-language-server: $schema=./assets/schema/henitai.schema.json",
      "includes:",
      "  - lib",
      "mutation:",
      "  operators: light",
      "  timeout: 10.0",
      "  max_mutants_per_line: 1",
      "  max_flaky_retries: 3",
      "  sampling:",
      "    ratio: 0.05",
      "    strategy: stratified",
      "reports_dir: reports",
      "thresholds:",
      "  high: 80",
      "  low: 60"
    ].freeze

    OPERATOR_METADATA = {
      "ArithmeticOperator" => ["Arithmetic operators", "a + b -> a - b"],
      "EqualityOperator" => ["Comparison operators", "a == b -> a != b"],
      "LogicalOperator" => ["Boolean operators", "a && b -> a || b"],
      "BooleanLiteral" => ["Boolean literals", "true -> false"],
      "ConditionalExpression" => ["Conditional branches", "if cond then ... end"],
      "StringLiteral" => ["String literals", '"foo" -> ""'],
      "ReturnValue" => ["Return expressions", "return x -> return nil"],
      "ArrayDeclaration" => ["Array literals", "[1, 2] -> []"],
      "HashLiteral" => ["Hash literals", "{ a: 1 } -> {}"],
      "RangeLiteral" => ["Range literals", "1..5 -> 1...5"],
      "SafeNavigation" => ["Safe navigation", "user&.name -> user.name"],
      "PatternMatch" => ["Pattern matching", "in { x: Integer } -> in { x: String }"],
      "BlockStatement" => ["Block statements", "{ do_work } -> {}"],
      "MethodExpression" => ["Method calls", "call_service -> nil"],
      "AssignmentExpression" => ["Assignment expressions", "x += 1 -> x -= 1"]
    }.freeze

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

    def run_command
      @command_halted = false
      options = parse_run_options
      return if @command_halted

      config = load_config(options)
      result = run_pipeline(options, config)
      exit(exit_status_for(result, config))
    rescue StandardError => e
      handle_run_error(e)
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
          all_logs: options[:all_logs],
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
        add_output_option(opts, options)
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

    def add_output_option(opts, options)
      opts.on("--all-logs", "--verbose", "Print all captured child logs") do
        options[:all_logs] = true
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

    def help_text
      <<~HELP
        Hen'i-tai 変異体 #{Henitai::VERSION} — Ruby 4 Mutation Testing

        Usage:
          henitai run [options] [SUBJECT_PATTERN...]
          henitai version
          henitai init [PATH]
          henitai operator list

        Examples:
          bundle exec henitai run
          bundle exec henitai run --since origin/main
          bundle exec henitai run 'Foo::Bar#my_method'
          bundle exec henitai run 'MyNamespace*' --operators full
          bundle exec henitai init
          bundle exec henitai operator list

        Run `henitai run --help` for full option list.
      HELP
    end

    def run_pipeline(options, config)
      runner = Runner.new(
        config:,
        subjects: subjects_from_argv,
        since: options[:since]
      )
      runner.run
    end

    def load_config(options)
      Configuration.load(
        path: options.fetch(:config, Configuration::CONFIG_FILE),
        overrides: configuration_overrides(options)
      )
    end

    def subjects_from_argv
      @argv.empty? ? nil : @argv.map { |expr| Subject.parse(expr) }
    end

    def handle_run_error(error)
      warn "#{error.class}: #{error.message}"
      exit 2
    end

    def exit_status_for(result, config)
      result.mutation_score.to_i >= config.thresholds.fetch(:low, 60) ? 0 : 1
    end

    def init_command
      path = @argv.shift || Configuration::CONFIG_FILE
      unexpected_arguments = @argv.dup
      warn "Unexpected arguments: #{unexpected_arguments.join(' ')}" unless unexpected_arguments.empty?
      exit 1 unless unexpected_arguments.empty?

      File.write(path, init_template)
      puts "Created #{path}"
    end

    def operator_command
      subcommand = @argv.shift
      case subcommand
      when "list" then puts operator_list_text
      when nil, "-h", "--help" then puts operator_help_text
      else
        warn "Unknown operator command: #{subcommand}"
        warn operator_help_text
        exit 1
      end
    rescue ArgumentError => e
      warn e.message
      exit 1
    end

    def init_template
      template = init_template_lines
      template << integration_block if include_default_integration?
      "#{template.join("\n")}\n"
    end

    def init_template_lines
      INIT_TEMPLATE_LINES.dup
    end

    def include_default_integration?
      return true unless $stdin.tty?

      print "Use the default RSpec integration? [Y/n] "
      response = $stdin.gets&.strip&.downcase
      response.nil? || response.empty? || !%w[n no].include?(response)
    end

    def integration_block
      <<~YAML.chomp
        integration:
          name: rspec
      YAML
    end

    def operator_help_text
      <<~HELP
        Hen'i-tai operator commands

        Usage:
          henitai operator list

        Run `henitai operator list` to see all built-in operators.
      HELP
    end

    def operator_list_text
      validate_operator_metadata!
      sections = [
        operator_list_section("Light set", Operator::LIGHT_SET),
        operator_list_section("Full set", Operator::FULL_SET)
      ]

      ["Available operators", *sections].join("\n")
    end

    def operator_list_section(title, names)
      rows = names.map { |name| operator_description_row(name) }
      ([title] + rows).join("\n")
    end

    def operator_description_row(name)
      description, example = operator_metadata[name] || fallback_operator_metadata

      format("- %<name>s: %<description>s (%<example>s)", name:, description:, example:)
    end

    def operator_metadata
      OPERATOR_METADATA
    end

    def fallback_operator_metadata
      ["No metadata available", "n/a"]
    end

    def validate_operator_metadata!
      missing = Operator::FULL_SET - operator_metadata.keys
      return if missing.empty?

      raise ArgumentError, "Missing operator metadata for: #{missing.join(', ')}"
    end
  end
  # rubocop:enable Metrics/ClassLength
end
