# frozen_string_literal: true

require "spec_helper"
require "json"
require "securerandom"
require "tmpdir"

RSpec.describe Henitai::SurvivorRerunStrategy do
  let(:dir) { Dir.mktmpdir }
  let(:namespace) { "RecipeE2E#{SecureRandom.hex(4)}" }

  after { FileUtils.remove_entry(dir) }

  def write_fixture(method_line)
    path = File.join(dir, "widget.rb")
    File.write(path, "module #{namespace}\n  class Widget\n    #{method_line}\n  end\nend\n")
    path
  end

  def resolve_subject(path, expression)
    Henitai::SubjectResolver.new.resolve_from_files([path])
                            .find { |subject| subject.expression == expression }
  end

  def survived_mutant(subject)
    mutants = Henitai::MutantGenerator.new.generate([subject], [Henitai::Operators::ArithmeticOperator.new])
    mutants.find { |mutant| mutant.mutated_node.children[1] == :- }
  end

  def write_report_and_recipes(mutant, recipes)
    report = File.join(dir, "mutation-report.json")
    survivor = { "stableId" => mutant.stable_id, "status" => "Survived" }
    File.write(report, JSON.generate("schemaVersion" => "1.0",
                                     "files" => { File.join(dir, "widget.rb") => { "mutants" => [survivor] } }))
    File.write(File.join(dir, Henitai::SurvivorActivationCache::FILENAME), JSON.generate(recipes))
    report
  end

  def strategy_for(report)
    analyzer = instance_double(Henitai::GitDiffAnalyzer, working_tree_changed_files: [])
    config = Struct.new(:includes).new([dir])
    Henitai::SurvivorRerunStrategy.new(survivors_from: report, config:, git_diff_analyzer: analyzer)
  end

  def recipes_for(mutant)
    JSON.parse(JSON.generate(Henitai::SurvivorActivationCache.compute([mutant])))
  end

  def stub_for(mutant)
    strategy_for(write_report_and_recipes(mutant, recipes_for(mutant))).try_recipe_run&.first
  end

  def mutant_for(method_line, expression)
    survived_mutant(resolve_subject(write_fixture(method_line), expression))
  end

  def activate_and_evaluate(stub)
    Henitai::Mutant::Activator.activate!(stub)
    yield
  end

  it "reruns an instance def through the recipe fast path" do
    stub = stub_for(mutant_for("def value = 1 + 2", "#{namespace}::Widget#value"))

    expect(activate_and_evaluate(stub) { Object.const_get(namespace)::Widget.new.value }).to eq(-1)
  end

  it "reruns a def self method through the recipe fast path" do
    stub = stub_for(mutant_for("def self.value = 1 + 2", "#{namespace}::Widget.value"))

    expect(activate_and_evaluate(stub) { Object.const_get(namespace)::Widget.value }).to eq(-1)
  end

  it "falls back to normal generation for a toplevel recipe without lexical fields" do
    mutant = mutant_for("def value = 1 + 2", "#{namespace}::Widget#value")
    recipes = recipes_for(mutant)
    recipes[mutant.stable_id]["activation"].delete("lexicalScope")

    expect(strategy_for(write_report_and_recipes(mutant, recipes)).try_recipe_run).to be_nil
  end

  it "falls back to normal generation for a toplevel recipe without the singleton flag" do
    mutant = mutant_for("def value = 1 + 2", "#{namespace}::Widget#value")
    recipes = recipes_for(mutant)
    recipes[mutant.stable_id]["activation"].delete("singleton")

    expect(strategy_for(write_report_and_recipes(mutant, recipes)).try_recipe_run).to be_nil
  end
end
