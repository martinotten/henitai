# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::Mutant::DefInjection do
  def subject_from(source, expression)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "sample.rb")
      File.write(path, source)
      Henitai::SubjectResolver.new.resolve_from_files([path]).find { |subject| subject.expression == expression }
    end
  end

  def mutant_for(subject, node, replacement_node = node)
    Henitai::Mutant.new(subject:, operator: "Fake", nodes: { original: node, mutated: replacement_node },
                        description: "fake", location: {})
  end

  it "wraps the spliced def in the original openers" do
    subject = subject_from("module A\n  class B\n    def value = 1 + 2\n  end\nend\n", "A::B#value")
    node = find_nodes(subject.ast_node, :send).first

    activation = described_class.build(mutant_for(subject, node), "1 - 2")

    expect(activation.source).to eq("module A; class B\n    def value = 1 - 2\nend; end\n")
  end

  it "removes the body of a replaced heredoc" do
    source = "class C\n  def text\n    <<~TXT\n      body\n    TXT\n  end\nend\n"
    subject = subject_from(source, "C#text")
    node = find_nodes(subject.ast_node, :str).first || find_nodes(subject.ast_node, :dstr).first

    activation = described_class.build(mutant_for(subject, node), '""')

    expect(activation.source).not_to include("body")
  end

  it "declines a subject without a recorded lexical scope" do
    resolved = subject_from("class D\n  def value = 1\nend\n", "D#value")
    subject = Henitai::Subject.new(namespace: "D", method_name: "value", ast_node: resolved.ast_node)
    node = resolved.ast_node.children.last

    expect(described_class.build(mutant_for(subject, node), "2")).to be_nil
  end
end
