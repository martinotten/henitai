# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::FidelityCheck do
  def mutants_for(source, operators: :light)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "sample.rb")
      File.write(path, source)
      subjects = Henitai::SubjectResolver.new.resolve_from_files([path])
      Henitai::MutantGenerator.new.generate(subjects, Henitai::Operator.for_set(operators))
    end
  end

  def mutant_for(source, description, operators: :light)
    description = Regexp.new("\\A#{Regexp.escape(description)}\\z") if description.is_a?(String)
    mutants = mutants_for(source, operators:)
    mutants.find { |mutant| description.match?(mutant.description) } ||
      raise("no mutant #{description.inspect} in #{mutants.map(&:description).uniq.inspect}")
  end

  def violation(mutant) = described_class.new.violation(mutant)

  it "accepts a mutant whose activated body differs only by the mutation" do
    mutant = mutant_for(<<~RUBY, "replaced + with -")
      class Sample
        def total(a, b)
          a + b
        end
      end
    RUBY

    expect(violation(mutant)).to be_nil
  end

  it "accepts a mutation inside a keyword argument value" do
    mutant = mutant_for(<<~RUBY, "replaced + with -")
      class Sample
        def call(x)
          build(size: x + 1)
        end
      end
    RUBY

    expect(violation(mutant)).to be_nil
  end

  it "accepts an index call that re-renders as an explicit [] call" do
    mutant = mutant_for(<<~RUBY, "replaced && with ||")
      class Sample
        def both(list)
          list[0] && list[1]
        end
      end
    RUBY

    expect(violation(mutant)).to be_nil
  end

  it "accepts a branch body spliced into the surrounding statement sequence" do
    mutant = mutant_for(<<~RUBY, "kept when branch 1")
      class Sample
        def pick(x)
          base = 1
          case x
          when 1
            extra = 2
            base + extra
          end
        end
      end
    RUBY

    expect(violation(mutant)).to be_nil
  end

  it "accepts an interpolation-free heredoc re-rendered as a plain string" do
    mutant = mutant_for(<<~RUBY, "removed interpolation from string")
      class Sample
        def usage
          <<~TXT
            Usage:

              run
          TXT
        end
      end
    RUBY

    expect(violation(mutant)).to be_nil
  end

  it "rejects a mutant that turns a local variable read into a method call" do
    mutant = mutant_for(<<~RUBY, "replaced && with lhs")
      class Sample
        def fetch(ready)
          if ready && (found = lookup)
            return found
          end

          nil
        end
      end
    RUBY

    expect(violation(mutant)).to include("differs from the reported mutation")
  end

  it "rejects a mutant that leaves a block attached to a removed call" do
    mutant = mutant_for(<<~RUBY, "replaced method call with nil", operators: :full)
      class Sample
        def any_match?(patterns, text)
          patterns.any? do |pattern|
            pattern.match?(text)
          end
        end
      end
    RUBY

    expect(violation(mutant)).to include("not valid Ruby")
  end

  it "rejects a negated condition that loses its parentheses" do
    mutant = mutant_for(<<~RUBY, "negated condition")
      class Sample
        def check(i)
          if i > 3
            1
          else
            2
          end
        end
      end
    RUBY

    expect(violation(mutant)).to include("differs from the reported mutation")
  end

  it "rejects a mutant that re-renders a one-parameter block as a destructuring block" do
    mutant = mutant_for(<<~RUBY, "replaced + with -")
      class Sample
        def sum(pairs)
          pairs.map { |pair| pair.first }.sum + 1
        end
      end
    RUBY

    expect(violation(mutant)).to include("changes the syntax form of `procarg0`")
  end

  it "rejects a mutant that turns keyword arguments into a positional hash" do
    mutant = mutant_for(<<~RUBY, /removed hash pair/, operators: :full)
      class Sample
        def call(x)
          build(name: x, size: 2)
        end
      end
    RUBY

    expect(violation(mutant)).to include("changes the syntax form of `kwargs`")
  end

  it "rejects a mutant spliced at a shifted offset after multibyte characters" do
    mutant = mutant_for(<<~RUBY, "replaced + with -")
      class Sample
        def check(x)
          label = "größe"
          x + 1 > 2
        end
      end
    RUBY

    expect(violation(mutant)).to match(/not valid Ruby|differs from the reported mutation/)
  end

  it "rejects a mutation outside the executed method body" do
    mutant = mutant_for(<<~RUBY, "replaced + with -")
      class Sample
        def call(x = 1 + 2)
          x
        end
      end
    RUBY

    expect(violation(mutant)).to include("outside the executed method body")
  end

  it "rejects an activation source that is not valid Ruby" do
    mutant = mutant_for(<<~RUBY, "replaced + with -")
      class Sample
        def each_doubled(x)
          yield x + 1
        end
      end
    RUBY

    expect(violation(mutant)).to include("not valid Ruby: Invalid yield")
  end

  it "reports an activation source that cannot be built" do
    mutant = mutant_for(<<~RUBY, "replaced + with -")
      class Sample
        def total(a, b) = a + b
      end
    RUBY
    allow(Henitai::Mutant::Activator).to receive(:activation_source_for).and_return(nil)

    expect(violation(mutant)).to eq("activation source could not be built")
  end

  it "reports a check that cannot complete instead of passing the mutant" do
    mutant = mutant_for(<<~RUBY, "replaced + with -")
      class Sample
        def total(a, b) = a + b
      end
    RUBY
    allow(Henitai::Mutant::Activator).to receive(:activation_source_for).and_raise(RuntimeError, "boom")

    expect(violation(mutant)).to eq("fidelity could not be verified (RuntimeError: boom)")
  end

  it "skips mutants it cannot relate to a method subject" do
    mutant = instance_double(Henitai::Mutant, original_node: nil)

    expect(violation(mutant)).to be_nil
  end
end
