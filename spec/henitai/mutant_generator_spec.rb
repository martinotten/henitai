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
                mutated_node: node,
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

  # ---------------------------------------------------------------------------
  # Private helper methods via send
  # ---------------------------------------------------------------------------

  describe "#sample_mutants" do
    let(:generator) { described_class.new }

    # L130 NoCoverage: sampling[:strategy] || :stratified
    # Der Fallback wird nie exercised weil Tests immer strategy: angeben.
    it "defaults strategy to :stratified when the sampling config has no :strategy key" do
      mutants = [
        instance_double(
          Henitai::Mutant,
          subject: instance_double(Henitai::Subject, expression: "Sample#alpha")
        )
      ]
      strategy = instance_double(Henitai::SamplingStrategy)
      config = instance_double(Henitai::Configuration, sampling: { ratio: 1.0 }) # kein :strategy

      allow(strategy).to receive(:sample).and_return(mutants)

      generator.send(:sample_mutants, mutants, config:, sampling_strategy: strategy)

      expect(strategy).to have_received(:sample).with(mutants, ratio: 1.0, strategy: :stratified)
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

    describe "#node_within_subject_range?" do
      # Build a lightweight node double with only the interface node_within_subject_range? touches.
      FakeExpression = Struct.new(:line, :last_line)
      FakeLocation   = Struct.new(:expression)

      def fake_node_at(start_line, end_line)
        Struct.new(:location).new(
          FakeLocation.new(FakeExpression.new(start_line, end_line))
        )
      end

      def visitor_with_range(start_line, end_line)
        subject = Henitai::Subject.new(
          namespace: "S",
          method_name: "run",
          source_location: { file: "s.rb", range: start_line..end_line }
        )
        visitor_class.new(subject, [], config: nil,
                                       arid_node_filter: arid_filter,
                                       syntax_validator: syntax_validator)
      end

      it "returns true when node range overlaps with subject range" do
        visitor = visitor_with_range(3, 8)
        expect(visitor.send(:node_within_subject_range?, fake_node_at(1, 5))).to be true
      end

      it "returns false when node range is entirely before subject range" do
        visitor = visitor_with_range(5, 8)
        expect(visitor.send(:node_within_subject_range?, fake_node_at(1, 3))).to be false
      end

      it "returns false when node range is entirely after subject range" do
        visitor = visitor_with_range(1, 5)
        expect(visitor.send(:node_within_subject_range?, fake_node_at(6, 9))).to be false
      end

      it "returns true when node and subject share exactly one boundary line" do
        visitor = visitor_with_range(1, 5)
        expect(visitor.send(:node_within_subject_range?, fake_node_at(5, 8))).to be true
      end

      it "returns true for any node when subject has no source_range" do
        subject = Henitai::Subject.new(
          namespace: "S",
          method_name: "run",
          source_location: { file: "s.rb", range: nil }
        )
        visitor = visitor_class.new(subject, [], config: nil,
                                                 arid_node_filter: arid_filter,
                                                 syntax_validator: syntax_validator)
        expect(visitor.send(:node_within_subject_range?, fake_node_at(99, 200))).to be true
      end

      it "returns true when the node has no location expression" do
        visitor = visitor_with_range(1, 5)
        node_without_loc = Struct.new(:location).new(FakeLocation.new(nil))
        expect(visitor.send(:node_within_subject_range?, node_without_loc)).to be true
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

      expect(subject).to receive(:source_range).once.and_return(1..5)

      visitor_class.new(subject, [], config: nil,
                                     arid_node_filter: arid_filter,
                                     syntax_validator: syntax_validator)
    end
  end
end
