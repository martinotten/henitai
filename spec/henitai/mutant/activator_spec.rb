# frozen_string_literal: true

require "fileutils"
require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::Mutant::Activator do
  def write_source(dir, source)
    path = File.join(dir, "sample.rb")
    File.write(path, source)
    path
  end

  def location_for(node)
    expression = node.location.expression
    {
      file: expression.source_buffer.name,
      start_line: expression.line,
      end_line: expression.last_line,
      start_col: expression.column,
      end_col: expression.last_column
    }
  end

  def class_eval_activation(source)
    Henitai::Mutant::Activation.new(source:, mode: :class_eval, file: described_class::EVAL_FILE)
  end

  def build_mutant(
    subject:,
    original_node:,
    mutated_node:,
    location:,
    precomputed_activation: nil
  )
    Henitai::Mutant.new(
      subject:,
      operator: "FakeOperator",
      nodes: {
        original: original_node,
        mutated: mutated_node
      },
      description: "replace node",
      location:,
      precomputed_activation:
    )
  end

  it "patches an instance method" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, <<~RUBY)
        class Sample
          def value
            1
          end
        end
      RUBY

      stub_const("Sample", Class.new)

      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).first
      original_node = find_nodes(subject.ast_node, :int).first
      mutant = build_mutant(
        subject:,
        original_node: original_node,
        mutated_node: Parser::AST::Node.new(:int, [2]),
        location: location_for(original_node)
      )

      described_class.activate!(mutant)

      expect(Sample.new.value).to eq(2)
    end
  end

  it "keeps the method's own source text for an unmutated control" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, <<~RUBY)
        class Sample
          def total(pairs)
            pairs.map { |pair| pair.first }.sum + 1
          end
        end
      RUBY

      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).first
      original_node = find_nodes(subject.ast_node, :send).find { |node| node.children[1] == :+ }
      mutant = build_mutant(subject:, original_node:, mutated_node: original_node,
                            location: location_for(original_node))

      expect(described_class.activation_source_for(mutant))
        .to include("pairs.map { |pair| pair.first }.sum + 1")
    end
  end

  it "patches the singleton copy of a module_function method", :aggregate_failures do
    Dir.mktmpdir do |dir|
      path = write_source(dir, <<~RUBY)
        module SampleFunctions
          module_function

          def value
            1
          end
        end
      RUBY

      stub_const("SampleFunctions", Module.new do
        module_function

        def value
          1
        end
      end)

      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).first
      original_node = find_nodes(subject.ast_node, :int).first
      mutant = build_mutant(
        subject:,
        original_node: original_node,
        mutated_node: Parser::AST::Node.new(:int, [2]),
        location: location_for(original_node)
      )

      described_class.activate!(mutant)

      # module_function copies the method onto the singleton; the mutation
      # must reach that copy or every mutant in such modules falsely survives.
      expect(SampleFunctions.value).to eq(2)
      expect(SampleFunctions.private_method_defined?(:value)).to be(true)
    end
  end

  it "does not clobber a distinct singleton method sharing an instance method's name" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, <<~RUBY)
        class SamplePair
          def value
            1
          end
        end
      RUBY

      stub_const("SamplePair", Class.new do
        def value = 1
        def self.value = :class_level
      end)

      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).first
      original_node = find_nodes(subject.ast_node, :int).first
      mutant = build_mutant(
        subject:,
        original_node: original_node,
        mutated_node: Parser::AST::Node.new(:int, [2]),
        location: location_for(original_node)
      )

      described_class.activate!(mutant)

      expect([SamplePair.new.value, SamplePair.value]).to eq([2, :class_level])
    end
  end

  it "passes the activator file and line to class_eval" do
    activator = described_class.new
    target = Class.new
    subject = Henitai::Subject.new(
      namespace: "Sample",
      method_name: "value",
      method_type: :instance
    )
    mutant = build_mutant(
      subject:,
      original_node: Parser::AST::Node.new(:int, [1]),
      mutated_node: Parser::AST::Node.new(:int, [2]),
      location: {
        file: "sample.rb",
        start_line: 1,
        end_line: 1,
        start_col: 0,
        end_col: 1
      },
      precomputed_activation: class_eval_activation("define_method(:value) do\n  2\nend\n")
    )

    allow(activator).to receive(:target_for).and_return(target)

    allow(target).to receive(:class_eval).and_return(nil)

    activator.activate!(mutant)

    expect(target).to have_received(:class_eval).with(
      mutant.precomputed_activation.source,
      described_class::EVAL_FILE,
      kind_of(Integer)
    )
  end

  it "patches a class method" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, <<~RUBY)
        class Sample
          def self.value
            1
          end
        end
      RUBY

      stub_const("Sample", Class.new)

      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).find do |candidate|
        candidate.expression == "Sample.value"
      end
      original_node = find_nodes(subject.ast_node, :int).first
      mutant = build_mutant(
        subject:,
        original_node: original_node,
        mutated_node: Parser::AST::Node.new(:int, [2]),
        location: location_for(original_node)
      )

      described_class.activate!(mutant)

      expect(Sample.value).to eq(2)
    end
  end

  it "loads an unloaded target constant before patching" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, <<~RUBY)
        class Gate4TransientSample
          def value
            1
          end
        end
      RUBY

      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).first
      original_node = find_nodes(subject.ast_node, :int).first
      mutant = build_mutant(
        subject:,
        original_node: original_node,
        mutated_node: Parser::AST::Node.new(:int, [2]),
        location: location_for(original_node)
      )

      described_class.activate!(mutant)

      expect(Gate4TransientSample.new.value).to eq(2)
    end
  end

  it "keeps the mutation active when the subject file is required again" do
    Dir.mktmpdir do |dir|
      source_dir = File.join(dir, "lib")
      spec_dir = File.join(dir, "spec")
      source_path = File.join(source_dir, "sample.rb")
      loader_path = File.join(spec_dir, "loader.rb")

      FileUtils.mkdir_p(source_dir)
      FileUtils.mkdir_p(spec_dir)
      File.write(
        source_path,
        <<~RUBY
          class LoadRedefinitionSample
            def value
              1
            end
          end
        RUBY
      )
      File.write(
        loader_path,
        <<~RUBY
          require_relative "../lib/sample"
        RUBY
      )

      subject = Henitai::SubjectResolver.new.resolve_from_files([source_path]).first
      original_node = find_nodes(subject.ast_node, :int).first
      mutant = build_mutant(
        subject:,
        original_node: original_node,
        mutated_node: Parser::AST::Node.new(:int, [2]),
        location: location_for(original_node)
      )

      described_class.activate!(mutant)
      load(loader_path)

      expect(LoadRedefinitionSample.new.value).to eq(2)
    end
  end

  it "patches the full method body for nested mutations" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, <<~RUBY)
        class Gate4NestedSample
          def wrap(value)
            value * 10
          end

          def value
            wrap(1 + 2)
          end
        end
      RUBY

      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).find do |candidate|
        candidate.expression == "Gate4NestedSample#value"
      end
      mutant = Henitai::MutantGenerator.new.generate(
        [subject],
        [Henitai::Operators::ArithmeticOperator.new]
      ).first

      described_class.activate!(mutant)

      expect(Gate4NestedSample.new.value).to eq(-10)
    end
  end

  it "uses raw source when the original node has no location metadata" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, <<~RUBY)
        class ActivatorHeredocFallbackSample
          def value
            <<~HTML
              <html>
                <body>hello</body>
              </html>
            HTML
          end
        end
      RUBY

      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).first
      body_node = subject.ast_node.children[2]
      original_node = Parser::AST::Node.new(:str, ["hello"])
      mutant = build_mutant(
        subject:,
        original_node:,
        mutated_node: Parser::AST::Node.new(:str, ["goodbye"]),
        location: location_for(find_nodes(subject.ast_node, :str).first)
      )

      allow(Unparser).to receive(:unparse).and_wrap_original do |original, node|
        raise "body unparse should not be used" if node.equal?(body_node)

        original.call(node)
      end

      described_class.activate!(mutant)

      expect(ActivatorHeredocFallbackSample.new.value).to include("<body>hello</body>")
    end
  end

  it "returns compile_error when class_eval raises SyntaxError" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, <<~RUBY)
        class ActivatorSyntaxErrorSample
          def value
            "hello"
          end
        end
      RUBY

      stub_const("ActivatorSyntaxErrorSample", Class.new)

      subject_obj = Henitai::SubjectResolver.new.resolve_from_files([path]).first
      original_node = find_nodes(subject_obj.ast_node, :str).first
      mutant = build_mutant(
        subject: subject_obj,
        original_node:,
        mutated_node: original_node,
        location: location_for(original_node),
        precomputed_activation: class_eval_activation("define_method(:value) do ||\n")
      )

      expect(described_class.activate!(mutant)).to eq(:compile_error)
    end
  end

  it "returns compile_error when Unparser cannot round-trip the replacement" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, <<~RUBY)
        class ActivatorRegexpSample
          def value
            /foo/
          end
        end
      RUBY

      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).first
      original_node = find_nodes(subject.ast_node, :regexp).first
      mutant = build_mutant(
        subject:,
        original_node:,
        mutated_node: Parser::CurrentRuby.parse("/bar/"),
        location: location_for(original_node)
      )

      allow(Unparser).to receive(:unparse).and_wrap_original do |original, node|
        raise "Could not find a round tripping solution for regexp" \
          if node.respond_to?(:type) && node.type == :regexp

        original.call(node)
      end

      expect(described_class.activate!(mutant)).to eq(:compile_error)
    end
  end

  it "infers the source file from AST metadata when none is provided" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, <<~RUBY)
        class ActivatorInferredSourceSample
          def value
            1
          end
        end
      RUBY

      resolved_subject = Henitai::SubjectResolver.new.resolve_from_files([path]).first
      subject = Henitai::Subject.new(
        namespace: resolved_subject.namespace,
        method_name: resolved_subject.method_name,
        method_type: resolved_subject.method_type,
        source_location: nil,
        ast_node: resolved_subject.ast_node
      )
      original_node = find_nodes(subject.ast_node, :int).first
      mutant = build_mutant(
        subject:,
        original_node: original_node,
        mutated_node: Parser::AST::Node.new(:int, [2]),
        location: location_for(original_node)
      )

      described_class.activate!(mutant)

      expect(ActivatorInferredSourceSample.new.value).to eq(2)
    end
  end

  it "raises when source file metadata cannot be determined" do
    subject = Henitai::Subject.new(
      namespace: "MissingActivatorSource",
      method_name: "value",
      method_type: :instance,
      ast_node: Struct.new(:location).new(nil)
    )
    mutant = build_mutant(
      subject:,
      original_node: Parser::AST::Node.new(:int, [1]),
      mutated_node: Parser::AST::Node.new(:int, [2]),
      location: {
        file: "missing.rb",
        start_line: 1,
        end_line: 1,
        start_col: 0,
        end_col: 1
      }
    )

    expect { described_class.activate!(mutant) }.to raise_error(NameError)
  end

  it "raises when the source file is missing from AST metadata" do
    subject = Henitai::Subject.new(
      namespace: "MissingActivatorAstSource",
      method_name: "value",
      method_type: :instance,
      ast_node: nil
    )
    mutant = build_mutant(
      subject:,
      original_node: Parser::AST::Node.new(:int, [1]),
      mutated_node: Parser::AST::Node.new(:int, [2]),
      location: {
        file: "missing.rb",
        start_line: 1,
        end_line: 1,
        start_col: 0,
        end_col: 1
      }
    )

    error = begin
      described_class.activate!(mutant)
    rescue StandardError => e
      e
    end

    expect(error.class).to be(NameError)
  end

  it "raises when AST metadata has no expression location" do
    subject = Henitai::Subject.new(
      namespace: "MissingActivatorExpression",
      method_name: "value",
      method_type: :instance,
      ast_node: Struct.new(:location).new(Struct.new(:expression).new(nil))
    )
    mutant = build_mutant(
      subject:,
      original_node: Parser::AST::Node.new(:int, [1]),
      mutated_node: Parser::AST::Node.new(:int, [2]),
      location: {
        file: "missing.rb",
        start_line: 1,
        end_line: 1,
        start_col: 0,
        end_col: 1
      }
    )

    expect { described_class.activate!(mutant) }.to raise_error(NameError)
  end

  it "serializes full parameter sets when activating a mutant" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, <<~RUBY)
        class ActivatorParamsSample
          def value(a, b = 1, *rest, c:, d: 2, **kwrest, &block)
            a + b
          end
        end
      RUBY

      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).first
      mutant = Henitai::MutantGenerator.new.generate(
        [subject],
        [Henitai::Operators::ArithmeticOperator.new]
      ).first

      described_class.activate!(mutant)

      expect(
        ActivatorParamsSample.new.value(3, 4, 5, c: 6, d: 7, e: 8) { :ok }
      ).to eq(-1)
    end
  end

  it "supports anonymous rest and keyword rest parameters" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, <<~RUBY)
        class ActivatorAnonymousRestSample
          def value(*, **)
            1
          end
        end
      RUBY

      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).first
      original_node = find_nodes(subject.ast_node, :int).first
      mutant = build_mutant(
        subject:,
        original_node: original_node,
        mutated_node: Parser::AST::Node.new(:int, [2]),
        location: location_for(original_node)
      )

      described_class.activate!(mutant)

      expect(ActivatorAnonymousRestSample.new.value(1, 2, a: 3)).to eq(2)
    end
  end

  it "supports forward arguments" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, <<~RUBY)
        class ActivatorForwardArgsSample
          def value(...)
            1
          end
        end
      RUBY

      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).first
      original_node = find_nodes(subject.ast_node, :int).first
      mutant = build_mutant(
        subject:,
        original_node: original_node,
        mutated_node: Parser::AST::Node.new(:int, [2]),
        location: location_for(original_node)
      )

      described_class.activate!(mutant)

      expect(ActivatorForwardArgsSample.new.value(1, 2, a: 3)).to eq(2)
    end
  end

  it "raises when the source file path is missing" do
    subject = Henitai::Subject.new(
      namespace: "MissingActivatorSourcePath",
      method_name: "value",
      method_type: :instance,
      source_location: {
        file: "/tmp/henitai-mutation-remediation/missing-activator-source.rb",
        range: 1..1
      },
      ast_node: nil
    )
    mutant = build_mutant(
      subject:,
      original_node: Parser::AST::Node.new(:int, [1]),
      mutated_node: Parser::AST::Node.new(:int, [2]),
      location: {
        file: "/tmp/henitai-mutation-remediation/missing-activator-source.rb",
        start_line: 1,
        end_line: 1,
        start_col: 0,
        end_col: 1
      }
    )

    expect { described_class.activate!(mutant) }.to raise_error(NameError)
  end

  it "mutates within rescue bodies" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, <<~RUBY)
        class ActivatorRescueSample
          def value(flag)
            begin
              raise "boom" if flag
              1
            rescue StandardError
              2
            end
          end
        end
      RUBY

      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).first
      original_node = find_nodes(subject.ast_node, :int).last
      mutant = build_mutant(
        subject:,
        original_node: original_node,
        mutated_node: Parser::AST::Node.new(:int, [3]),
        location: location_for(original_node)
      )

      described_class.activate!(mutant)

      expect(ActivatorRescueSample.new.value(true)).to eq(3)
    end
  end

  it "leaves the method unchanged when the original node is not found" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, <<~RUBY)
        class ActivatorNoMatchSample
          def value
            1
          end
        end
      RUBY

      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).first
      unrelated_node = Parser::CurrentRuby.parse("2")
      mutant = build_mutant(
        subject:,
        original_node: unrelated_node,
        mutated_node: Parser::AST::Node.new(:int, [3]),
        location: location_for(find_nodes(subject.ast_node, :int).first)
      )

      described_class.activate!(mutant)

      expect(ActivatorNoMatchSample.new.value).to eq(1)
    end
  end

  it "leaves the method unchanged when the original range is invalid" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, <<~RUBY)
        class ActivatorInvalidRangeSample
          def value
            1
          end
        end
      RUBY

      stub_const("ActivatorInvalidRangeSample", Class.new)
      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).first
      original_node = find_nodes(subject.ast_node, :int).first
      expression = original_node.location.expression
      invalid_range = Struct.new(:begin_pos, :end_pos).new(
        expression.begin_pos + 1,
        expression.begin_pos
      )
      malformed_original = Struct.new(:location).new(
        Struct.new(:expression).new(invalid_range)
      )
      mutant = build_mutant(
        subject:,
        original_node: malformed_original,
        mutated_node: Parser::AST::Node.new(:int, [2]),
        location: location_for(original_node)
      )

      described_class.activate!(mutant)

      expect(ActivatorInvalidRangeSample.new.value).to eq(1)
    end
  end

  it "leaves the method unchanged when the original node lacks location metadata" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, <<~RUBY)
        class ActivatorLocationlessSample
          def value
            1
          end
        end
      RUBY

      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).first
      locationless_node = Parser::AST::Node.new(:int, [1])
      mutant = build_mutant(
        subject:,
        original_node: locationless_node,
        mutated_node: Parser::AST::Node.new(:int, [3]),
        location: location_for(find_nodes(subject.ast_node, :int).first)
      )

      described_class.activate!(mutant)

      expect(ActivatorLocationlessSample.new.value).to eq(1)
    end
  end

  it "rejects wildcard subjects" do
    subject = Henitai::Subject.new(namespace: "Sample", method_name: nil)
    mutant = Struct.new(:subject, :mutated_node).new(
      subject,
      Parser::AST::Node.new(:int, [2])
    )

    expect { described_class.activate!(mutant) }
      .to raise_error(ArgumentError, /wildcard/i)
  end

  it "uses source_file_from_ast when target constant is not loaded" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, <<~RUBY)
        class RealTransientSample
          def value
            1
          end
        end
      RUBY
      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).first
      original_node = find_nodes(subject.ast_node, :int).first
      mutant = build_mutant(
        subject:,
        original_node: original_node,
        mutated_node: Parser::AST::Node.new(:int, [2]),
        location: location_for(original_node)
      )

      call_count = 0
      allow(Object).to receive(:const_get).and_wrap_original do |original, *args|
        if args == ["RealTransientSample"]
          call_count += 1
          raise NameError, "Not found" if call_count == 1
        end

        original.call(*args)
      end

      described_class.activate!(mutant)

      expect(RealTransientSample.new.value).to eq(2)
    end
  end

  it "infers the source file from the AST after a target lookup miss" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, <<~RUBY)
        class ActivatorAstFallbackSample
          def value
            1
          end
        end
      RUBY
      resolved = Henitai::SubjectResolver.new.resolve_from_files([path]).first
      subject = Henitai::Subject.new(
        namespace: resolved.namespace,
        method_name: resolved.method_name,
        method_type: resolved.method_type,
        source_location: nil,
        ast_node: resolved.ast_node
      )
      original_node = find_nodes(subject.ast_node, :int).first
      mutant = build_mutant(
        subject:,
        original_node:,
        mutated_node: Parser::AST::Node.new(:int, [2]),
        location: location_for(original_node)
      )

      lookup_count = 0
      allow(Object).to receive(:const_get).and_wrap_original do |original, *args|
        if args == ["ActivatorAstFallbackSample"]
          lookup_count += 1
          raise NameError, "Not found" if lookup_count == 1
        end

        original.call(*args)
      end

      described_class.activate!(mutant)

      expect(ActivatorAstFallbackSample.new.value).to eq(2)
    end
  end

  describe "def injection in the original lexical scope" do
    # Loads the source (as the test environment would), resolves its subject
    # and activates an unmutated control or the given mutation.
    let(:defined_constants) { [] }

    after do
      defined_constants.each { |name| Object.class_eval { remove_const(name) if const_defined?(name, false) } }
    end

    def activate_in(dir, source, expression, constants:, mutate: nil)
      defined_constants.concat(constants)
      path = load_once(dir, source)
      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).find { |s| s.expression == expression }
      described_class.activate!(mutation_of(subject, mutate))
    end

    # Without +mutate+, an unmutated control of the method's body.
    def mutation_of(subject, mutate)
      node = mutate ? mutate.fetch(:find).call(subject.ast_node) : subject.ast_node.children.last
      mutated = mutate ? mutate.fetch(:to) : node
      build_mutant(subject:, original_node: node, mutated_node: mutated, location: location_for(node))
    end

    def load_once(dir, source)
      path = File.join(dir, "sample.rb")
      return path if File.exist?(path)

      write_source(dir, source)
      load path
      path
    end

    def int(value) = Parser::AST::Node.new(:int, [value])

    def first_int(value) = { find: ->(ast) { find_nodes(ast, :int).find { |n| n.children == [value] } }, to: nil }

    it "resolves constants of an enclosing module" do
      Dir.mktmpdir do |dir|
        source = <<~RUBY
          module DiOuter
            LIMIT = 10
            class Inner
              def capped(x) = [x, LIMIT].min + 1
            end
          end
        RUBY
        activate_in(dir, source, "DiOuter::Inner#capped", constants: ["DiOuter"],
                                                          mutate: first_int(1).merge(to: int(2)))

        expect(DiOuter::Inner.new.capped(20)).to eq(12)
      end
    end

    it "resolves a class method's own constants" do
      Dir.mktmpdir do |dir|
        source = <<~RUBY
          class DiConfig
            RATE = 3
            def self.rate = RATE + 1
          end
        RUBY
        activate_in(dir, source, "DiConfig.rate", constants: ["DiConfig"], mutate: first_int(1).merge(to: int(5)))

        expect(DiConfig.rate).to eq(8)
      end
    end

    it "keeps implicit super, yield and block_given? working" do
      Dir.mktmpdir do |dir|
        source = <<~RUBY
          class DiBase
            def total(x) = x * 2
          end
          class DiChild < DiBase
            def total(x) = super + 1
            def each_tier = yield(4)
            def maybe = block_given? ? yield : :none
          end
        RUBY
        constants = %w[DiBase DiChild]
        activate_in(dir, source, "DiChild#total", constants:, mutate: first_int(1).merge(to: int(3)))
        activate_in(dir, source, "DiChild#each_tier", constants:)
        activate_in(dir, source, "DiChild#maybe", constants:)

        expect([DiChild.new.total(2), DiChild.new.each_tier { |n| n * 10 }, DiChild.new.maybe { :given }])
          .to eq([7, 40, :given])
      end
    end

    it "keeps argument forwarding and default values with operators" do
      Dir.mktmpdir do |dir|
        source = <<~RUBY
          class DiForward
            def build(a, b = 1 + 1) = [a, b]
            def forward(...) = build(...)
          end
        RUBY
        activate_in(dir, source, "DiForward#forward", constants: ["DiForward"])
        activate_in(dir, source, "DiForward#build", constants: ["DiForward"])

        expect([DiForward.new.forward(5), DiForward.new.forward(5, 9)]).to eq([[5, 2], [5, 9]])
      end
    end

    it "keeps __FILE__, __LINE__, frozen string literals and private visibility" do
      Dir.mktmpdir do |dir|
        source = <<~RUBY
          # frozen_string_literal: true

          class DiFacts
            private

            def facts = [File.basename(__FILE__), __LINE__, "s".frozen?]
          end
        RUBY
        activate_in(dir, source, "DiFacts#facts", constants: ["DiFacts"])

        expect([DiFacts.instance_method(:facts).bind_call(DiFacts.new), DiFacts.private_method_defined?(:facts)])
          .to eq([["sample.rb", 6, true], true])
      end
    end

    it "describes a top-level activation in the original file and at the def's line" do
      Dir.mktmpdir do |dir|
        path = write_source(dir, "module DiPlace\n  class Spot\n    def value = 1\n  end\nend\n")
        subject = Henitai::SubjectResolver.new.resolve_from_files([path]).first
        node = subject.ast_node.children.last
        activation = described_class.activation_for(build_mutant(subject:, original_node: node, mutated_node: node,
                                                                 location: location_for(node)))

        expect([activation.mode, activation.file, activation.source.lines[activation.def_offset]])
          .to eq([:toplevel, path, "    def value = 1\n"])
      end
    end
  end

  describe ".activation_source_for" do
    it "returns the subject's def inside its class opener" do
      Dir.mktmpdir do |dir|
        path = write_source(dir, <<~RUBY)
          class ActivationSourceSample
            def value
              1 + 1
            end
          end
        RUBY

        subject = Henitai::SubjectResolver.new.resolve_from_files([path]).first
        mutant = Henitai::MutantGenerator.new.generate(
          [subject],
          [Henitai::Operators::ArithmeticOperator.new]
        ).first

        source = described_class.activation_source_for(mutant)

        expect(source).to eq("class ActivationSourceSample\n  def value\n    1 - 1\n  end\nend\n")
      end
    end

    it "returns nil when the source cannot be computed" do
      mutant = instance_double(Henitai::Mutant, original_node: nil)
      allow(mutant).to receive(:subject).and_raise(RuntimeError, "boom")

      expect(described_class.activation_source_for(mutant)).to be_nil
    end
  end

  it "falls back to define_method for a subject without a recorded lexical scope" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, "class FallbackSample\n  def value = 1 + 1\nend\n")
      resolved = Henitai::SubjectResolver.new.resolve_from_files([path]).first
      subject = Henitai::Subject.new(namespace: "FallbackSample", method_name: "value",
                                     source_location: { file: path, range: 2..2 }, ast_node: resolved.ast_node)
      node = find_nodes(subject.ast_node, :send).first

      activation = described_class.activation_for(build_mutant(subject:, original_node: node, mutated_node: node,
                                                               location: location_for(node)))

      expect([activation.mode, activation.source.include?("define_method(:value)")]).to eq([:class_eval, true])
    end
  end

  describe "#activate! with precomputed_activation" do
    it "uses the precomputed source instead of recomputing from AST" do
      Dir.mktmpdir do |dir|
        path = write_source(dir, <<~RUBY)
          class PrecomputedActivationSample
            def value
              1 + 1
            end
          end
        RUBY

        subject = Henitai::SubjectResolver.new.resolve_from_files([path]).first
        mutant = Henitai::MutantGenerator.new.generate(
          [subject],
          [Henitai::Operators::ArithmeticOperator.new]
        ).first

        precomputed = class_eval_activation("define_method(:value) do\n  42\nend\n")
        mutant = build_mutant(
          subject: mutant.subject,
          original_node: mutant.original_node,
          mutated_node: mutant.mutated_node,
          location: mutant.location,
          precomputed_activation: precomputed
        )

        described_class.activate!(mutant)

        expect(PrecomputedActivationSample.new.value).to eq(42)
      end
    end
  end

  it "does not suppress warn calls emitted by the loaded source file" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, <<~RUBY)
        class Gate4WarningSample
          warn "deprecation notice from loaded file"
          def value
            1
          end
        end
      RUBY

      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).first
      original_node = find_nodes(subject.ast_node, :int).first
      mutant = build_mutant(
        subject:,
        original_node: original_node,
        mutated_node: Parser::AST::Node.new(:int, [2]),
        location: location_for(original_node)
      )

      expect { described_class.activate!(mutant) }.to output(
        /deprecation notice from loaded file/
      ).to_stderr
    end
  end
end
