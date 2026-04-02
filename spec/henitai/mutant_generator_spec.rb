# frozen_string_literal: true

require "fileutils"
require "spec_helper"
require "tmpdir"

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

  it "keeps the highest priority mutant on a line" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, "lib/sample.rb", <<~RUBY)
        class Sample
          def announce
            1 + 2 == 3
          end
        end
      RUBY

      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).first
      operators = [
        Henitai::Operators::EqualityOperator.new,
        Henitai::Operators::ArithmeticOperator.new
      ]

      mutants = described_class.new.generate([subject], operators)

      expect(mutants.map(&:description)).to eq(["replaced + with -"])
    end
  end

  it "honors the configured max mutants per line" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, "lib/sample.rb", <<~RUBY)
        class Sample
          def announce
            1 + 2 - 3
          end
        end
      RUBY

      config = write_configuration(
        dir,
        <<~YAML
          mutation:
            max_mutants_per_line: 2
        YAML
      )
      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).first

      mutants = described_class.new.generate(
        [subject],
        [Henitai::Operators::ArithmeticOperator.new],
        config:
      )

      expect(mutants.map(&:description)).to contain_exactly(
        "replaced + with -",
        "replaced - with +"
      )
    end
  end

  # L49 NoCoverage: config&.max_mutants_per_line || 1
  # Bei config: nil muss der || 1-Fallback greifen — ein Mutant pro Zeile.
  it "defaults to 1 mutant per line when no config is given" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, "lib/sample.rb", <<~RUBY)
        class Sample
          def announce
            1 + 2 - 3
          end
        end
      RUBY

      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).first
      mutants = described_class.new.generate(
        [subject],
        [Henitai::Operators::ArithmeticOperator.new],
        config: nil
      )

      lines = mutants.map { |m| m.location[:start_line] }
      expect(lines).to eq(lines.uniq)
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

  describe "#line_key" do
    let(:generator) { described_class.new }

    # L135 NoCoverage: ReturnValue auf [file, start_line]-Array
    it "returns a two-element array of file and start_line" do
      mutant = instance_double(
        Henitai::Mutant,
        location: { file: "lib/foo.rb", start_line: 7 }
      )
      expect(generator.send(:line_key, mutant)).to eq(["lib/foo.rb", 7])
    end
  end

  describe "#mutant_priority_key" do
    let(:generator) { described_class.new }

    # L142 NoCoverage: ReturnValue auf Priority-Key-Array
    it "returns a three-element priority key" do
      mutant = instance_double(
        Henitai::Mutant,
        operator: "ArithmeticOperator",
        location: { start_col: 4 },
        description: "replaced + with -"
      )
      key = generator.send(:mutant_priority_key, mutant)
      expect(key).to eq([0, 4, "replaced + with -"])
    end

    # L144 NoCoverage: mutant.location[:start_col] || 0
    it "falls back to column 0 when start_col is absent" do
      mutant = instance_double(
        Henitai::Mutant,
        operator: "ArithmeticOperator",
        location: { start_col: nil },
        description: "x"
      )
      expect(generator.send(:mutant_priority_key, mutant)[1]).to eq(0)
    end
  end

  describe "#operator_priority_map" do
    let(:generator) { described_class.new }

    # L150 Survived: ReturnValue — Methode gibt 0 zurück statt Hash
    it "returns a Hash keyed by operator name" do
      expect(generator.send(:operator_priority_map)).to include("ArithmeticOperator" => 0)
    end

    it "is memoized across calls" do
      first_map = generator.send(:operator_priority_map)
      second_map = generator.send(:operator_priority_map)

      expect(first_map).to be(second_map)
    end

    it "returns the map size as the fallback priority for unknown operators" do
      map = generator.send(:operator_priority_map)
      expect(generator.send(:operator_priority, "UnknownOperator")).to eq(map.length)
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

    def make_int_operator
      stub_const("Henitai::FakeIntOperatorForVisitor",
                 Class.new(Henitai::Operator) do
                   def self.node_types = [:int]

                   def mutate(node, subject:)
                     [build_mutant(subject:, original_node: node, mutated_node: node, description: "fake int")]
                   end
                 end)
      Henitai::FakeIntOperatorForVisitor.new
    end

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

    # L102: ranges_overlap? ReturnValue → 0 (truthy)
    # L106: left.begin <= right.end → left.begin != right.end
    describe "#ranges_overlap?" do
      let(:visitor) do
        subject = Henitai::Subject.new(namespace: "S", method_name: "run")
        visitor_class.new(subject, [], config: nil,
                                       arid_node_filter: arid_filter,
                                       syntax_validator: syntax_validator)
      end

      it "returns true for overlapping ranges" do
        expect(visitor.send(:ranges_overlap?, 1..5, 3..8)).to be true
      end

      # Tötet L102: wenn 0 (truthy) zurückgegeben wird, passt dieser Test noch —
      # aber der false-Fall unten kann mit ReturnValue 0 nicht mehr false sein.
      it "returns false for disjoint ranges" do
        expect(visitor.send(:ranges_overlap?, 1..3, 5..8)).to be false
      end

      # Tötet L106: left.begin != right.end gibt true für (6..9, 1..5):
      # 6 != 5 = true && 1 <= 9 = true → fälschlich true.
      # Original: 6 <= 5 = false → korrekt false.
      it "returns false when left range begins after right range ends (L106 boundary)" do
        expect(visitor.send(:ranges_overlap?, 6..9, 1..5)).to be false
      end

      it "returns true when ranges share exactly one boundary line" do
        expect(visitor.send(:ranges_overlap?, 1..5, 5..8)).to be true
      end
    end
  end
end
