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

  def build_mutant(
    subject:,
    original_node:,
    mutated_node:,
    location:,
    precomputed_activation_source: nil
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
      precomputed_activation_source:
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
      precomputed_activation_source: "define_method(:value) do\n  2\nend\n"
    )

    allow(activator).to receive(:target_for).and_return(target)

    activator_file, activate_line = described_class.instance_method(:activate!).source_location
    expected_line = activate_line + 8

    allow(target).to receive(:class_eval).and_return(nil)

    activator.activate!(mutant)

    expect(target).to have_received(:class_eval).with(
      mutant.precomputed_activation_source,
      activator_file,
      expected_line
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
        precomputed_activation_source: "define_method(:value) do ||\n"
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

    expect { described_class.activate!(mutant) }.to raise_error(NameError)
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

  describe ".activation_source_for" do
    it "includes define_method(:value) in the returned source" do
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

        expect(source).to include("define_method(:value)")
      end
    end

    it "returns nil when the source cannot be computed" do
      mutant = instance_double(Henitai::Mutant)
      allow(mutant).to receive(:subject).and_raise(RuntimeError, "boom")

      expect(described_class.activation_source_for(mutant)).to be_nil
    end
  end

  describe "#activate! with precomputed_activation_source" do
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

        precomputed = "define_method(:value) do\n  42\nend\n"
        mutant = build_mutant(
          subject: mutant.subject,
          original_node: mutant.original_node,
          mutated_node: mutant.mutated_node,
          location: mutant.location,
          precomputed_activation_source: precomputed
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
