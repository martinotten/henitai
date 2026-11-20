# frozen_string_literal: true

require "spec_helper"
require "json"
require "stringio"

# Adding an operator or an operator set touches components that must agree:
# Operator::SETS, the Operators autoload list, the config schema and
# validator, the CLI metadata and `operator list` output, and the
# `henitai:disable` name whitelist. Release 0.4.0 updated some and silently
# broke the rest — every operator's own unit spec stayed green while
# `# henitai:disable HashKeyType` started aborting runs, because nothing
# asserted what other components do with the registered names.
#
# These examples are driven off HARD_SET: the widest set is the registry.
# Set nesting itself is pinned by spec/henitai/operator_spec.rb.
# rubocop:disable RSpec/DescribeClass
RSpec.describe "Operator registry" do
  def registry
    Henitai::Operator::HARD_SET
  end

  def operator_class(name)
    Henitai::Operators.const_get(name)
  rescue NameError
    nil
  end

  def operator_list_output
    original = $stdout
    $stdout = StringIO.new
    Henitai::CLI.new(%w[operator list]).run
    $stdout.string
  ensure
    $stdout = original
  end

  def operator_source_files
    Dir[File.expand_path("../../lib/henitai/operators/*.rb", __dir__)]
  end

  it "autoloads every registered operator" do
    expect(registry.reject { |name| operator_class(name) }).to be_empty
  end

  it "declares node_types for every registered operator" do
    expect(registry.reject { |name| operator_class(name)&.node_types.is_a?(Array) }).to be_empty
  end

  it "provides CLI metadata for every registered operator" do
    expect(registry - Henitai::CLI::OperatorCommand::OPERATOR_METADATA.keys).to be_empty
  end

  it "lists every registered operator in `henitai operator list`" do
    output = operator_list_output

    expect(registry.reject { |name| output.include?(name) }).to be_empty
  end

  it "accepts every registered operator name in a `henitai:disable` directive" do
    expect(registry - Henitai::MutationSkipDirectives::VALID_OPERATOR_NAMES).to be_empty
  end

  it "offers the declared operator sets in the config schema" do
    schema = JSON.parse(File.read(File.expand_path("../../assets/schema/henitai.schema.json", __dir__)))
    enum = schema.dig("properties", "mutation", "properties", "operators", "enum")

    expect(enum).to match_array(Henitai::Operator::SETS.keys.map(&:to_s))
  end

  it "accepts the declared operator sets in the configuration validator" do
    expect(Henitai::ConfigurationValidator::VALID_OPERATORS).to match_array(Henitai::Operator::SETS.keys)
  end

  # Descriptions reach the terminal summary, the survivor list, the JSON
  # report and MutantIdentity.stable_id. A newline breaks every single-line
  # surface at once, and the way it gets in is an operator rendering an AST
  # node it assumed was a simple literal (see HashLiteral pair labels).
  # Exercised against a fixture broad enough to trip most operators; an
  # operator that emits nothing here is simply not covered by this guard.
  def description_fixture
    <<~RUBY
      def sample(a, b)
        config = { { x: 1 } => 2, [3] => 4, "s" => 5, :"multi\nline" => 6, k: 7 }
        total = a + b - 1
        total += 1
        flag = a == b && a != b || !a
        list = [1, 2].map { |value| value * 2 }
        a&.deep&.chain
        return "text" if a > 1 && (1..5).cover?(b)
        /foo+/.match?("bar")
        case config
        in { k: Integer } then true
        else false
        end
      end
    RUBY
  end

  def all_descriptions_for(operator_class)
    root = Henitai::SourceParser.parse(description_fixture)
    subject = Henitai::Subject.new(namespace: "Example", method_name: "sample")

    operator_class.node_types.flat_map do |type|
      find_nodes(root, type).flat_map do |node|
        operator_class.new.mutate(node, subject:).map(&:description)
      end
    end
  end

  it "emits only single-line mutant descriptions" do
    multiline = registry.select do |name|
      all_descriptions_for(operator_class(name)).any? { |description| description.include?("\n") }
    end

    expect(multiline).to be_empty
  end

  # Every operator building Parser AST nodes must pull the parser in itself:
  # relying on a sibling operator or SourceParser to have loaded it first
  # makes the file a NameError waiting for a lazily-loaded consumer.
  it "requires parser_current in every operator source that builds Parser AST nodes" do
    offenders = operator_source_files.select do |file|
      source = File.read(file)
      source.include?("Parser::AST::Node") && !source.include?('require_relative "../parser_current"')
    end

    expect(offenders.map { |file| File.basename(file) }).to be_empty
  end
end
# rubocop:enable RSpec/DescribeClass
