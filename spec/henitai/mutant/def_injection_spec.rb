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

    expect(activation.source).to eq("module A; class B; def value = 1 - 2; end; end\n")
  end

  it "removes the body of a replaced heredoc" do
    source = "class C\n  def text\n    <<~TXT\n      body\n    TXT\n  end\nend\n"
    subject = subject_from(source, "C#text")
    node = find_nodes(subject.ast_node, :str).first || find_nodes(subject.ast_node, :dstr).first

    activation = described_class.build(mutant_for(subject, node), '""')

    expect(activation.source).not_to include("body")
  end

  def replace_literal(source, expression, replacement)
    subject = subject_from(source, expression)
    node = find_nodes(subject.ast_node, :int).first
    described_class.build(mutant_for(subject, node), replacement)
  end

  def evaluate(activation)
    TOPLEVEL_BINDING.eval(activation.source, activation.file, activation.line)
  end

  it "keeps __LINE__ of a def on the first line" do
    activation = replace_literal("class DefInjectionLineOne; def value = 0; end\n",
                                 "DefInjectionLineOne#value", "__LINE__")

    evaluate(activation)

    expect(DefInjectionLineOne.new.value).to eq(1)
  end

  it "keeps __LINE__ of a def on the second line" do
    activation = replace_literal("class DefInjectionLineTwo\n  def value = 0\nend\n",
                                 "DefInjectionLineTwo#value", "__LINE__")

    evaluate(activation)

    expect(DefInjectionLineTwo.new.value).to eq(2)
  end

  it "activates a top-level singleton def without openers" do
    stub_const("DefInjectionTop", Class.new)
    activation = replace_literal("def DefInjectionTop.bar = 0\n", "DefInjectionTop.bar", "1")

    evaluate(activation)

    expect(DefInjectionTop.bar).to eq(1)
  end

  it "does not treat a prose comment mentioning a magic comment as one" do
    source = "# we set frozen_string_literal: true here\nclass DefInjectionProse\n  def value = 0\nend\n"
    activation = replace_literal(source, "DefInjectionProse#value", "1")

    expect(activation.source).not_to include("we set")
  end

  it "keeps a real magic comment in the activation source" do
    source = "# frozen_string_literal: true\nclass DefInjectionMagic\n  def value = 0\nend\n"
    activation = replace_literal(source, "DefInjectionMagic#value", "1")

    expect(activation.source).to start_with("# frozen_string_literal: true\n")
  end

  it "keeps an emacs magic comment with several keys in the activation source" do
    line = "# -*- coding: utf-8; frozen_string_literal: true -*-"
    source = "#{line}\nclass DefInjectionEmacs\n  def value = 0\nend\n"
    activation = replace_literal(source, "DefInjectionEmacs#value", "1")

    expect(activation.source).to start_with("#{line}\n")
  end

  it "drops an emacs comment without a supported magic key from the activation source" do
    source = "# -*- mode: ruby -*-\nclass DefInjectionMode\n  def value = 0\nend\n"
    activation = replace_literal(source, "DefInjectionMode#value", "1")

    expect(activation.source).not_to include("mode: ruby")
  end

  it "declines a subject without a recorded lexical scope" do
    resolved = subject_from("class D\n  def value = 1\nend\n", "D#value")
    subject = Henitai::Subject.new(namespace: "D", method_name: "value", ast_node: resolved.ast_node)
    node = resolved.ast_node.children.last

    expect(described_class.build(mutant_for(subject, node), "2")).to be_nil
  end
end
