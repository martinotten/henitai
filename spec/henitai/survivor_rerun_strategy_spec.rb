# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"

RSpec.describe Henitai::SurvivorRerunStrategy do
  def write_survivor_report(dir)
    path = File.join(dir, "mutation-report.json")
    File.write(path, JSON.generate(
                       "schemaVersion" => "1.0",
                       "files" => {
                         "lib/sample.rb" => {
                           "mutants" => [{ "stableId" => "abc", "status" => "Survived" }]
                         }
                       }
                     ))
    path
  end

  def recipe(overrides = {})
    {
      "activationSource" => "1",
      "namespace" => "Sample",
      "methodName" => "value",
      "sourceFile" => "lib/sample.rb",
      "operator" => "ArithmeticOperator",
      "description" => "changed arithmetic"
    }.merge(overrides)
  end

  def write_recipes(dir, value)
    File.write(
      File.join(dir, "activation-recipes.json"),
      JSON.generate("abc" => value)
    )
  end

  def strategy_for(report_path)
    config = Struct.new(:includes).new(["lib"])
    analyzer = instance_double(Henitai::GitDiffAnalyzer, working_tree_changed_files: [])
    described_class.new(survivors_from: report_path, config:, git_diff_analyzer: analyzer)
  end

  describe "#active?" do
    it "is active when a survivor report is configured" do
      strategy = described_class.new(
        survivors_from: "reports/mutation-report.json",
        config: nil,
        git_diff_analyzer: nil
      )

      expect(strategy).to be_active
    end

    it "is inactive without a survivor report" do
      strategy = described_class.new(
        survivors_from: nil,
        config: nil,
        git_diff_analyzer: nil
      )

      expect(strategy).not_to be_active
    end
  end

  describe "#try_recipe_run" do
    it "builds mutants with the cached operator" do
      Dir.mktmpdir do |dir|
        report_path = write_survivor_report(dir)
        write_recipes(dir, recipe)

        expect(strategy_for(report_path).try_recipe_run.first.operator).to eq("ArithmeticOperator")
      end
    end

    it "uses an empty location when the recipe omits it" do
      Dir.mktmpdir do |dir|
        report_path = write_survivor_report(dir)
        write_recipes(dir, recipe)

        expect(strategy_for(report_path).try_recipe_run.first.location).to eq({})
      end
    end

    it "does not warn when every cached survivor is matched" do
      Dir.mktmpdir do |dir|
        report_path = write_survivor_report(dir)
        write_recipes(dir, recipe)

        expect { strategy_for(report_path).try_recipe_run }.not_to output.to_stderr
      end
    end
  end

  describe "#apply_selection" do
    it "warns with the number of unmatched survivors" do
      Dir.mktmpdir do |dir|
        report_path = write_survivor_report(dir)

        expect { strategy_for(report_path).apply_selection([]) }
          .to output(/WARNING: 1 prior survivors could not be matched/).to_stderr
      end
    end
  end
end
