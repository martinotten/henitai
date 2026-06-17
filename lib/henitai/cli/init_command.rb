# frozen_string_literal: true

module Henitai
  class CLI
    # Implements `henitai init`: writes a starter `.henitai.yml`, optionally
    # prompting for the default RSpec integration when stdin is a TTY. Mixed
    # into {CLI}.
    module InitCommand
      INIT_TEMPLATE_LINES = [
        "# yaml-language-server: $schema=./assets/schema/henitai.schema.json",
        "includes:",
        "  - lib",
        "mutation:",
        "  operators: light",
        "  timeout: 10.0",
        "  max_flaky_retries: 3",
        "  sampling:",
        "    ratio: 0.05",
        "    strategy: stratified",
        "reports_dir: reports",
        "thresholds:",
        "  high: 80",
        "  low: 60"
      ].freeze

      private

      def init_command
        path = @argv.shift || Configuration::CONFIG_FILE
        unexpected_arguments = @argv.dup
        warn "Unexpected arguments: #{unexpected_arguments.join(' ')}" unless unexpected_arguments.empty?
        exit 1 unless unexpected_arguments.empty?

        File.write(path, init_template)
        puts "Created #{path}"
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
    end
  end
end
