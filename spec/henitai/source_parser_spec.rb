# frozen_string_literal: true

require "spec_helper"
require "unparser"

RSpec.describe Henitai::SourceParser do
  def collect_node_types(node)
    types = []
    queue = [node]

    until queue.empty?
      current = queue.shift
      types << current.type if current.respond_to?(:type)
      queue.concat(current.children.compact) if current.respond_to?(:children)
    end

    types.uniq
  end

  def mutation_surface_source
    <<~RUBY
      class Sample
        def answer = 1 + 2
      end

      values = [1, 2, 3]
      thresholds = { low: 1 }
      range = 1..3
      user = profile&.user
      total += 1 if enabled && active
      case payload
      in { answer: } then answer
      end
    RUBY
  end

  def expected_mutation_surface_types
    %i[
      class
      def
      send
      and
      csend
      array
      hash
      irange
      op_asgn
      case_match
      in_pattern
    ]
  end

  it "preserves the source path in AST locations" do
    ast = described_class.parse(
      "class Sample; def answer = 1 + 2; end",
      path: "sample.rb"
    )

    expect(ast.location.expression.source_buffer.name).to eq("sample.rb")
  end

  it "uses (string) as the default source path" do
    ast = described_class.parse("1 + 2")

    expect(ast.location.expression.source_buffer.name).to eq("(string)")
  end

  it "uses (string) as the default source path on the instance API" do
    ast = described_class.new.parse("1 + 2")

    expect(ast.location.expression.source_buffer.name).to eq("(string)")
  end

  it "exposes the node types needed for mutation operators" do
    ast = described_class.parse(mutation_surface_source, path: "sample.rb")

    expect(collect_node_types(ast)).to include(*expected_mutation_surface_types)
  end

  it "can be unparsed back to source" do
    ast = described_class.parse(
      "class Sample; def answer = 1 + 2; end",
      path: "sample.rb"
    )

    expect(Unparser.unparse(ast)).to eq(<<~RUBY)
      class Sample
        def answer
          1 + 2
        end
      end
    RUBY
  end

  describe ".parse_file caching" do
    around do |example|
      described_class.clear_cache!
      example.run
      described_class.clear_cache!
    end

    it "returns the same object on repeated calls without a file change" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "sample.rb")
        File.write(path, "class A; def m = 1; end")

        first  = described_class.parse_file(path)
        second = described_class.parse_file(path)

        expect(second).to be(first)
      end
    end

    it "returns a fresh parse when the file mtime changes" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "sample.rb")
        File.write(path, "class A; def m = 1; end")
        first = described_class.parse_file(path)

        # Advance mtime by touching the file content (guarantees a different mtime)
        sleep 0.01
        File.write(path, "class A; def m = 2; end")
        second = described_class.parse_file(path)

        expect(second).not_to be(first)
      end
    end

    it "caches different files under separate entries" do
      Dir.mktmpdir do |dir|
        path_a = File.join(dir, "a.rb")
        path_b = File.join(dir, "b.rb")
        File.write(path_a, "class A; end")
        File.write(path_b, "class B; end")

        ast_a = described_class.parse_file(path_a)
        ast_b = described_class.parse_file(path_b)

        expect(
          [
            ast_a.equal?(ast_b),
            described_class.parse_file(path_a).equal?(ast_a),
            described_class.parse_file(path_b).equal?(ast_b)
          ]
        ).to eq([false, true, true])
      end
    end

    it "does not call File.read a second time for a cached file" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "sample.rb")
        File.write(path, "class A; def m = 1; end")

        allow(File).to receive(:read).and_call_original
        described_class.parse_file(path)

        described_class.parse_file(path)

        expect(File).to have_received(:read).once.with(path)
      end
    end
  end
end
