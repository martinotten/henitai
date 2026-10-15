# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::StillbornFilter do
  def build_mutant(source)
    node = Henitai::SourceParser.parse(source)

    Henitai::Mutant.new(
      subject: Henitai::Subject.new(namespace: "Example", method_name: "example"),
      operator: "ArithmeticOperator",
      nodes: { original: node, mutated: node },
      description: "example mutation",
      location: {
        file: "(string)",
        start_line: 1,
        end_line: 1,
        start_col: 0,
        end_col: 1
      }
    )
  end

  describe "for a resolved method" do
    # Raw operator output, before the generator's own stillborn filtering.
    def mutants_of(source, operators: :full)
      Dir.mktmpdir do |dir|
        path = File.join(dir, "sample.rb")
        File.write(path, source)
        subjects = Henitai::SubjectResolver.new.resolve_from_files([path])
        Henitai::Operator.for_set(operators).flat_map do |operator|
          subjects.flat_map { |subject| operator_mutants(operator, subject) }
        end
      end
    end

    def operator_mutants(operator, subject)
      nodes = operator.class.node_types.flat_map { |type| find_nodes(subject.ast_node, type) }
      nodes.flat_map { |node| operator.mutate(node, subject:) }
    end

    it "keeps a keyword-argument removal that is only valid inside its call" do
      mutants = mutants_of("class Sample\n  def call(x) = build(name: x, size: 2)\nend\n")
      removals = mutants.select { |mutant| mutant.description.start_with?("removed hash pair") }

      expect(removals.map { |mutant| described_class.new.suppressed?(mutant) }).to eq([false, false])
    end

    def verdicts(source, operators: :light)
      mutants_of(source, operators:).to_h { |mutant| [mutant.description, described_class.new.suppressed?(mutant)] }
    end

    it "suppresses a mutant that removes the assignment of a local read later" do
      source = <<~RUBY
        class Sample
          def call(x)
            return fast if ready? && (fast = compute(x))
            fast
          end
        end
      RUBY

      expect(verdicts(source).values_at("replaced condition with true", "replaced && with lhs", "negated condition"))
        .to eq([true, true, false])
    end

    it "keeps a mutant whose removed local is still assigned elsewhere or never read" do
      source = <<~RUBY
        class Sample
          def call(x, fast = nil)
            if ready? && (slow = compute(x)) then 1 end
            fast
          end
        end
      RUBY

      expect(verdicts(source).values_at("replaced condition with true", "replaced && with lhs")).to eq([false, false])
    end

    it "keeps a mutant of a method that already calls a method named like one of its locals" do
      source = <<~RUBY
        class Sample
          def call(x)
            value + 1
            value = x
            value
          end
        end
      RUBY

      expect(verdicts(source)["replaced + with -"]).to be(false)
    end

    it "keeps a mutated next guard inside a block" do
      mutants = mutants_of("class Sample\n  def call(xs) = xs.each { |x| next if x > 3 }\nend\n", operators: :light)
      guards = mutants.select { |mutant| mutant.description == "replaced condition with true" }

      expect(guards.map { |mutant| described_class.new.suppressed?(mutant) }).to eq([false])
    end
  end

  it "keeps syntactically valid mutants" do
    mutant = build_mutant("1")

    expect(described_class.new.suppressed?(mutant)).to be(false)
  end

  it "suppresses mutants that unparse to invalid Ruby" do
    mutant = build_mutant("1")

    allow(Unparser).to receive(:unparse).with(mutant.mutated_node).and_return("def")

    expect(described_class.new.suppressed?(mutant)).to be(true)
  end

  it "suppresses mutants when unparsing raises" do
    mutant = build_mutant("1")

    allow(Unparser).to receive(:unparse).with(mutant.mutated_node).and_raise(StandardError, "boom")

    expect(described_class.new.suppressed?(mutant)).to be(true)
  end

  it "does not flag return mutants as stillborn" do
    mutant = build_mutant("return 1")

    expect(described_class.new.suppressed?(mutant)).to be(false)
  end

  it "suppresses rendered source that breaks the wrapper syntax" do
    mutant = build_mutant("1")
    allow(Unparser).to receive(:unparse).with(mutant.mutated_node).and_return("end")

    expect(described_class.new.suppressed?(mutant)).to be(true)
  end
end
