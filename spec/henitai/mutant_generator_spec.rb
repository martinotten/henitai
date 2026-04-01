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
            foo.bar
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
end
