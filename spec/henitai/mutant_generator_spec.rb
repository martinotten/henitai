# frozen_string_literal: true

require "fileutils"
require "spec_helper"
require "tmpdir"

module Henitai
  class FakeIntOperatorForVisitor < Operator
    def self.node_types = [:int]

    def mutate(node, subject:)
      [build_mutant(subject:, original_node: node, mutated_node: node, description: "fake int")]
    end
  end
end

RSpec.describe Henitai::MutantGenerator do
  def write_source(dir, relative_path, source)
    path = File.join(dir, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, source)
    path
  end

  def write_configuration(dir, yaml)
    path = File.join(dir, ".henitai.yml")
    File.write(path, yaml)
    Henitai::Configuration.load(path:)
  end

  def source_with_two_subjects
    <<~RUBY
      class Sample
        def alpha
          1
          2
        end

        def beta
          3
        end
      end
    RUBY
  end

  it "generates mutants only within the subject line range" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, "lib/sample.rb", source_with_two_subjects)
      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).find do |candidate|
        candidate.expression == "Sample#alpha"
      end

      fake_operator = stub_const(
        "Henitai::FakeIntOperator",
        Class.new(Henitai::Operator) do
          def self.node_types
            [:int]
          end

          def mutate(node, subject:)
            [
              build_mutant(
                subject:,
                original_node: node,
                mutated_node: node.updated(nil, [node.children.first + 10]),
                description: "fake int"
              )
            ]
          end
        end
      )

      mutants = described_class.new.generate([subject], [fake_operator])

      expect(mutants.map { |mutant| mutant.location[:start_line] }).to eq([3, 4])
    end
  end

  it "reuses the resolved subject AST instead of reparsing the file" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, "lib/sample.rb", source_with_two_subjects)
      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).find do |candidate|
        candidate.expression == "Sample#alpha"
      end

      fake_operator = stub_const(
        "Henitai::FakeIntOperatorForSubjectAst",
        Class.new(Henitai::Operator) do
          def self.node_types
            [:int]
          end

          def mutate(node, subject:)
            [
              build_mutant(
                subject:,
                original_node: node,
                mutated_node: node,
                description: "fake int"
              )
            ]
          end
        end
      )

      allow(Henitai::SourceParser).to receive(:parse_file).and_raise("reparsed subject")

      mutants = described_class.new.generate([subject], [fake_operator])

      expect(mutants.map(&:description)).to include("fake int")
    end
  end

  it "returns no mutants for a subject without source metadata" do
    fake_operator = stub_const(
      "Henitai::FakeIntOperator",
      Class.new(Henitai::Operator) do
        def self.node_types
          [:int]
        end

        def mutate(node, subject:)
          [
            build_mutant(
              subject:,
              original_node: node,
              mutated_node: node,
              description: "fake int"
            )
          ]
        end
      end
    )

    subject = Henitai::Subject.new(
      namespace: "Sample",
      method_name: "alpha"
    )

    mutants = described_class.new.generate([subject], [fake_operator])

    expect(mutants).to eq([])
  end

  it "returns no mutants when source parsing yields no node" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, "lib/sample.rb", "class Sample; end\n")
      subject = Henitai::Subject.new(
        namespace: "Sample",
        method_name: "alpha",
        source_location: { file: path, range: 1..1 }
      )
      fake_operator = stub_const(
        "Henitai::FakeIntOperator",
        Class.new(Henitai::Operator) do
          def self.node_types
            [:int]
          end

          def mutate(node, subject:)
            [
              build_mutant(
                subject:,
                original_node: node,
                mutated_node: node,
                description: "fake int"
              )
            ]
          end
        end
      )

      source_parser = instance_double(Henitai::SourceParser)
      allow(Henitai::SourceParser).to receive(:new).and_return(source_parser)
      allow(source_parser).to receive(:parse_file).with(path).and_return(nil)
      allow(Henitai::MutantGenerator::SubjectVisitor).to receive(:new)

      described_class.new.generate([subject], [fake_operator])

      expect(Henitai::MutantGenerator::SubjectVisitor).not_to have_received(:new)
    end
  end

  it "skips arid nodes before applying operators" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, "lib/sample.rb", <<~RUBY)
        class Sample
          def announce
            puts "x"
          end
        end
      RUBY

      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).first
      fake_operator = stub_const(
        "Henitai::FakeSendOperator",
        Class.new(Henitai::Operator) do
          def self.node_types
            [:send]
          end

          def mutate(node, subject:)
            [
              build_mutant(
                subject:,
                original_node: node,
                mutated_node: node,
                description: "fake send"
              )
            ]
          end
        end
      )

      mutants = described_class.new.generate([subject], [fake_operator])

      expect(mutants).to eq([])
    end
  end

  it "still mutates non-arid send nodes" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, "lib/sample.rb", <<~RUBY)
        class Sample
          def announce
            foo
          end
        end
      RUBY

      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).first
      fake_operator = stub_const(
        "Henitai::FakeSendOperator",
        Class.new(Henitai::Operator) do
          def self.node_types
            [:send]
          end

          def mutate(node, subject:)
            [
              build_mutant(
                subject:,
                original_node: node,
                mutated_node: node,
                description: "fake send"
              )
            ]
          end
        end
      )

      mutants = described_class.new.generate([subject], [fake_operator])

      expect(mutants.map(&:description)).to include("fake send")
    end
  end

  it "discards stillborn mutants after operator application" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, "lib/sample.rb", <<~RUBY)
        class Sample
          def announce
            foo
          end
        end
      RUBY

      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).first
      fake_operator = stub_const(
        "Henitai::FakeSendOperator",
        Class.new(Henitai::Operator) do
          def self.node_types
            [:send]
          end

          def mutate(node, subject:)
            [
              build_mutant(
                subject:,
                original_node: node,
                mutated_node: node,
                description: "valid send"
              ),
              build_mutant(
                subject:,
                original_node: node,
                mutated_node: Object.new,
                description: "invalid send"
              )
            ]
          end
        end
      )

      mutants = described_class.new.generate([subject], [fake_operator])

      expect(mutants.map(&:description)).to eq(["valid send"])
    end
  end

  describe "returns all mutations from all operators on the same line" do
    subject(:descriptions) do
      Dir.mktmpdir do |dir|
        path = write_source(dir, "lib/sample.rb", <<~RUBY)
          class Sample
            def announce
              1 + 2 == 3
            end
          end
        RUBY

        subj = Henitai::SubjectResolver.new.resolve_from_files([path]).first
        operators = [
          Henitai::Operators::EqualityOperator.new,
          Henitai::Operators::ArithmeticOperator.new
        ]

        described_class.new.generate([subj], operators).map(&:description)
      end
    end

    it { is_expected.to include("replaced + with -") }
    it { is_expected.to include("replaced == with !=") }
    it { expect(descriptions.length).to be > 1 }
  end

  describe "mutant identities" do
    def chain_mutants(dir)
      path = write_source(dir, "lib/chain.rb", "class Chain\n  def run(x)\n    x.a.b.c\n  end\nend\n")
      subjects = Henitai::SubjectResolver.new.resolve_from_files([path])
      described_class.new.generate(subjects, [Henitai::Operators::MethodExpression.new])
    end

    it "gives nested calls that start at the same position distinct identities" do
      Dir.mktmpdir do |dir|
        ids = chain_mutants(dir).map(&:stable_id)

        expect(ids.uniq.size).to eq(ids.size)
      end
    end

    it "keeps disambiguated identities stable when lines are added above the subject" do
      Dir.mktmpdir do |dir|
        ids = chain_mutants(dir).map(&:stable_id)
        path = File.join(dir, "lib/chain.rb")
        File.write(path, "# drift\n#{File.read(path)}")
        drifted_ids = described_class.new.generate(
          Henitai::SubjectResolver.new.resolve_from_files([path]),
          [Henitai::Operators::MethodExpression.new]
        ).map(&:stable_id)

        expect(drifted_ids).to eq(ids)
      end
    end

    it "keeps one mutant when two operators produce the same program" do
      Dir.mktmpdir do |dir|
        path = write_source(dir, "lib/guard.rb", "class Guard\n  def run(x)\n    return true if x\n    1\n  end\nend\n")
        subjects = Henitai::SubjectResolver.new.resolve_from_files([path])
        mutants = described_class.new.generate(subjects, Henitai::Operator.for_set(:light))
        programs = mutants.map { |mutant| Henitai::Mutant::Activator.activation_source_for(mutant) }

        expect(programs.size).to eq(programs.uniq.size)
      end
    end

    it "does not mutate the implicit value of a shorthand hash pair" do
      Dir.mktmpdir do |dir|
        path = write_source(dir, "lib/short.rb", "class Short\n  def run = build(config:)\nend\n")
        subjects = Henitai::SubjectResolver.new.resolve_from_files([path])
        mutants = described_class.new.generate(subjects, [Henitai::Operators::MethodExpression.new])

        expect(mutants.map { |mutant| mutant.original_node.location.expression.source }).to eq(["build(config:)"])
      end
    end

    it "keeps the identity of a mutant that does not collide" do
      Dir.mktmpdir do |dir|
        path = write_source(dir, "lib/single.rb", "class Single\n  def run(x) = x + 1\nend\n")
        subjects = Henitai::SubjectResolver.new.resolve_from_files([path])
        mutant = described_class.new.generate(subjects, [Henitai::Operators::ArithmeticOperator.new]).first
        undisambiguated = Henitai::Mutant.new(subject: mutant.subject, operator: mutant.operator,
                                              nodes: { original: mutant.original_node, mutated: mutant.mutated_node },
                                              description: mutant.description, location: mutant.location)

        expect(mutant.stable_id).to eq(undisambiguated.stable_id)
      end
    end
  end

  it "applies stratified sampling when configured" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, "lib/sample.rb", <<~RUBY)
        class Sample
          def announce
            1 + 2
          end
        end
      RUBY

      config = write_configuration(
        dir,
        <<~YAML
          mutation:
            sampling:
              ratio: 0.0
              strategy: stratified
        YAML
      )
      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).first

      mutants = described_class.new.generate(
        [subject],
        [Henitai::Operators::ArithmeticOperator.new],
        config:
      )

      expect(mutants).to eq([])
    end
  end

  it "skips sampling when asked not to sample" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, "lib/sample.rb", "class Sample\n  def announce\n    1 + 2\n  end\nend\n")
      config = write_configuration(dir, "mutation:\n  sampling:\n    ratio: 0.0\n    strategy: stratified\n")
      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).first

      mutants = described_class.new.generate(
        [subject], [Henitai::Operators::ArithmeticOperator.new], config:, sample: false
      )

      expect(mutants).not_to be_empty
    end
  end

  it "passes the configured sampling seed to the strategy" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, "lib/sample.rb", "class Sample\n  def announce\n    1 + 2\n  end\nend\n")
      config = write_configuration(dir, <<~YAML)
        mutation:
          sampling:
            ratio: 0.5
            strategy: stratified
            seed: 7
      YAML
      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).first
      strategy = Henitai::SamplingStrategy.new
      allow(Henitai::SamplingStrategy).to receive(:new).and_return(strategy)
      allow(strategy).to receive(:sample).and_call_original

      described_class.new.generate([subject], [Henitai::Operators::ArithmeticOperator.new], config:)

      expect(strategy).to have_received(:sample).with(anything, ratio: 0.5, strategy: "stratified", seed: 7)
    end
  end

  it "uses the default sampling seed when none is configured" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, "lib/sample.rb", "class Sample\n  def announce\n    1 + 2\n  end\nend\n")
      config = write_configuration(dir, <<~YAML)
        mutation:
          sampling:
            ratio: 0.5
            strategy: stratified
      YAML
      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).first
      strategy = Henitai::SamplingStrategy.new
      allow(Henitai::SamplingStrategy).to receive(:new).and_return(strategy)
      allow(strategy).to receive(:sample).and_call_original

      described_class.new.generate([subject], [Henitai::Operators::ArithmeticOperator.new], config:)

      expect(strategy).to have_received(:sample).with(
        anything, ratio: 0.5, strategy: "stratified", seed: Henitai::SamplingStrategy::DEFAULT_SEED
      )
    end
  end

  it "computes activation sources only for the sampled mutants", :aggregate_failures do
    Dir.mktmpdir do |dir|
      path = write_source(dir, "lib/sample.rb", <<~RUBY)
        class Sample
          def announce
            1 + 2 + 3 + 4 + 5 + 6
          end
        end
      RUBY
      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).first
      operators = [Henitai::Operators::ArithmeticOperator.new]
      config = write_configuration(
        dir,
        <<~YAML
          mutation:
            sampling:
              ratio: 0.5
              strategy: stratified
        YAML
      )
      unsampled = described_class.new.generate([subject], operators).size

      allow(Henitai::Mutant::Activator).to receive(:activation_source_for).and_call_original
      sampled = described_class.new.generate([subject], operators, config:)

      expect(sampled.size).to be < unsampled
      expect(Henitai::Mutant::Activator).to have_received(:activation_source_for).exactly(sampled.size).times
    end
  end

  # ---------------------------------------------------------------------------
  # SubjectVisitor — direkte Tests der nested class
  # Ursache aller Survived-Mutanten L73–L106: Der Coverage-Tracker attributiert
  # Testausführung nicht zur nested class, nur zu MutantGenerator#generate.
  # ---------------------------------------------------------------------------

  describe "SubjectVisitor" do
    let(:visitor_class) { Henitai::MutantGenerator::SubjectVisitor }
    let(:arid_filter)   { Henitai::AridNodeFilter.new }
    let(:syntax_validator) { Henitai::SyntaxValidator.new }

    def make_int_operator = Henitai::FakeIntOperatorForVisitor.new

    def make_subject_for(path, expression)
      Henitai::SubjectResolver.new.resolve_from_files([path]).find do |s|
        s.expression == expression
      end
    end

    def new_visitor(subject, operators, arid_node_filter: arid_filter,
                    syntax_validator: self.syntax_validator, config: nil)
      visitor_class.new(
        subject,
        operators,
        config:,
        arid_node_filter:,
        syntax_validator:
      )
    end

    # L73: process delegiert an walk — wenn walk nicht aufgerufen wird,
    # bleiben @mutants leer.
    it "populates mutants when process is called (L73 ReturnValue)" do
      Dir.mktmpdir do |dir|
        path = write_source(dir, "lib/sample.rb", <<~RUBY)
          class Sample
            def run
              1
            end
          end
        RUBY

        subject = make_subject_for(path, "Sample#run")
        visitor = new_visitor(subject, [make_int_operator])
        visitor.process(Henitai::SourceParser.parse_file(path))

        expect(visitor.mutants).not_to be_empty
      end
    end

    # L79: return unless node.is_a?(Parser::AST::Node)
    # Negation würde versuchen .children auf non-AST-Kindknoten aufzurufen.
    it "skips non-AST children without raising (L79 ConditionalExpression)" do
      Dir.mktmpdir do |dir|
        path = write_source(dir, "lib/sample.rb", <<~RUBY)
          class Sample
            def run
              :a_symbol
            end
          end
        RUBY

        subject = make_subject_for(path, "Sample#run")
        visitor = new_visitor(subject, [])

        expect { visitor.process(Henitai::SourceParser.parse_file(path)) }.not_to raise_error
      end
    end

    # L81: apply_operators if node_within_subject_range?
    # Negation würde Operatoren auf Knoten AUSSERHALB der Range anwenden.
    it "does not generate mutants for nodes outside the subject range (L81 ConditionalExpression)" do
      Dir.mktmpdir do |dir|
        path = write_source(dir, "lib/sample.rb", <<~RUBY)
          class Sample
            def alpha
              1
            end

            def beta
              2
            end
          end
        RUBY

        alpha = make_subject_for(path, "Sample#alpha")
        beta  = make_subject_for(path, "Sample#beta")
        visitor = new_visitor(alpha, [make_int_operator])
        visitor.process(Henitai::SourceParser.parse_file(path))

        mutant_lines = visitor.mutants.map { |m| m.location[:start_line] }
        beta_lines   = (beta.source_range.begin..beta.source_range.end).to_a
        expect(mutant_lines).not_to include(*beta_lines)
      end
    end

    # L88: return if @arid_node_filter.suppressed?
    # Negation würde unterdrückte Knoten mutieren.
    it "skips nodes suppressed by the arid filter (L88 ConditionalExpression)" do
      Dir.mktmpdir do |dir|
        path = write_source(dir, "lib/sample.rb", <<~RUBY)
          class Sample
            def run
              1
            end
          end
        RUBY

        subject = make_subject_for(path, "Sample#run")
        always_suppress = instance_double(Henitai::AridNodeFilter)
        allow(always_suppress).to receive(:suppressed?).and_return(true)

        visitor = new_visitor(subject, [make_int_operator], arid_node_filter: always_suppress)
        visitor.process(Henitai::SourceParser.parse_file(path))

        expect(visitor.mutants).to be_empty
      end
    end

    # L92: @mutants << mutant if @syntax_validator.valid?(mutant)
    # Negation würde nur invalide Mutanten sammeln.
    it "does not collect mutants that fail syntax validation (L92 ConditionalExpression)" do
      Dir.mktmpdir do |dir|
        path = write_source(dir, "lib/sample.rb", <<~RUBY)
          class Sample
            def run
              1
            end
          end
        RUBY

        subject = make_subject_for(path, "Sample#run")
        always_invalid = instance_double(Henitai::SyntaxValidator)
        allow(always_invalid).to receive(:valid?).and_return(false)

        visitor = new_visitor(subject, [make_int_operator], syntax_validator: always_invalid)
        visitor.process(Henitai::SourceParser.parse_file(path))

        expect(visitor.mutants).to be_empty
      end
    end

    # L99: location && @subject.source_range → nur location
    # Divergiert wenn source_range nil ist aber location nicht:
    # Mutation fällt durch zu ranges_overlap?(range, nil) → NoMethodError.
    it "does not raise when the subject has no source_range (L99 LogicalOperator)" do
      Dir.mktmpdir do |dir|
        path = write_source(dir, "lib/sample.rb", <<~RUBY)
          class Sample
            def run
              1
            end
          end
        RUBY

        subject_no_range = Henitai::Subject.new(
          namespace: "Sample",
          method_name: "run",
          source_location: { file: path, range: nil }
        )

        visitor = new_visitor(subject_no_range, [make_int_operator])

        expect { visitor.process(Henitai::SourceParser.parse_file(path)) }.not_to raise_error
      end
    end

    it "still generates mutants when the subject has no source_range (L99 LogicalOperator)" do
      Dir.mktmpdir do |dir|
        path = write_source(dir, "lib/sample.rb", <<~RUBY)
          class Sample
            def run
              1
            end
          end
        RUBY

        subject_no_range = Henitai::Subject.new(
          namespace: "Sample",
          method_name: "run",
          source_location: { file: path, range: nil }
        )

        visitor = new_visitor(subject_no_range, [make_int_operator])
        visitor.process(Henitai::SourceParser.parse_file(path))

        expect(visitor.mutants).not_to be_empty
      end
    end

    it "does not generate standalone mutations for str segments embedded in dstr nodes" do
      Dir.mktmpdir do |dir|
        path = write_source(dir, "lib/sample.rb", <<~RUBY)
          class Sample
            def greet(name)
              "Hello, \#{name}!"
            end
          end
        RUBY

        subject = make_subject_for(path, "Sample#greet")
        visitor = new_visitor(subject, [Henitai::Operators::StringLiteral.new])
        visitor.process(Henitai::SourceParser.parse_file(path))

        # The dstr node as a whole must be mutated (removing the interpolation),
        # but the embedded str segment "Hello, " must not produce a standalone
        # mutation — that would insert a quoted literal into raw-text position
        # and generate a SyntaxError when the mutant is activated.
        expect(visitor.mutants.map { |m| m.original_node.type }).to all(eq(:dstr))
      end
    end

    {
      "a heredoc" => "<<~TXT\n      hello \#{x}\n    TXT",
      "a regexp" => "/abc/",
      "a word array" => "%w[alpha beta]",
      "an interpolated symbol" => ":\"k\#{x}\""
    }.each do |container, expression|
      it "does not mutate raw text segments inside #{container}" do
        Dir.mktmpdir do |dir|
          path = write_source(dir, "lib/sample.rb", "class Sample\n  def run(x)\n    #{expression}\n  end\nend\n")
          subject = make_subject_for(path, "Sample#run")
          visitor = new_visitor(subject, [Henitai::Operators::StringLiteral.new])
          visitor.process(Henitai::SourceParser.parse_file(path))

          expect(visitor.mutants.map { |m| m.original_node.type }).not_to include(:str)
        end
      end
    end

    it "mutates string elements of a bracketed array literal" do
      Dir.mktmpdir do |dir|
        path = write_source(dir, "lib/sample.rb", "class Sample\n  def run\n    [\"alpha\", \"beta\"]\n  end\nend\n")
        subject = make_subject_for(path, "Sample#run")
        visitor = new_visitor(subject, [Henitai::Operators::StringLiteral.new])
        visitor.process(Henitai::SourceParser.parse_file(path))

        expect(visitor.mutants.map { |m| m.original_node.type }).to include(:str)
      end
    end

    it "pre-computes subject source_range once during initialization" do
      subject = instance_double(
        Henitai::Subject,
        namespace: "S",
        expression: "S#run",
        source_range: 1..5,
        source_file: nil
      )

      allow(subject).to receive(:source_range).and_return(1..5)

      visitor_class.new(subject, [], config: nil,
                                     arid_node_filter: arid_filter,
                                     syntax_validator: syntax_validator)

      expect(subject).to have_received(:source_range).once
    end
  end
end
