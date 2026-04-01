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
end
