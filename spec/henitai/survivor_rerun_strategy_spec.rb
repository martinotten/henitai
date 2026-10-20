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
      "activation" => { "source" => "1", "mode" => "class_eval" },
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
    it "skips the recipe fast path when the worktree changes cannot be read" do
      Dir.mktmpdir do |dir|
        report_path = write_survivor_report(dir)
        write_recipes(dir, recipe)
        analyzer = instance_double(Henitai::GitDiffAnalyzer)
        allow(analyzer).to receive(:working_tree_changed_files).and_raise(RuntimeError, "git unavailable")
        strategy = described_class.new(
          survivors_from: report_path,
          config: Struct.new(:includes).new(["lib"]),
          git_diff_analyzer: analyzer
        )

        expect(strategy.try_recipe_run).to be_nil
      end
    end

    it "builds mutants with the cached operator" do
      Dir.mktmpdir do |dir|
        report_path = write_survivor_report(dir)
        write_recipes(dir, recipe)

        expect(strategy_for(report_path).try_recipe_run.first.operator).to eq("ArithmeticOperator")
      end
    end

    it "reports the replacement stored in the recipe" do
      Dir.mktmpdir do |dir|
        report_path = write_survivor_report(dir)
        write_recipes(dir, recipe("replacement" => "x - 1"))

        expect(strategy_for(report_path).try_recipe_run.first.mutated_source).to eq("x - 1")
      end
    end

    it "falls back to unparsing for a legacy recipe without a replacement" do
      Dir.mktmpdir do |dir|
        report_path = write_survivor_report(dir)
        write_recipes(dir, recipe)

        expect(strategy_for(report_path).try_recipe_run.first.mutated_source).to eq("")
      end
    end

    it "does not replay a recipe without an activation" do
      Dir.mktmpdir do |dir|
        report_path = write_survivor_report(dir)
        write_recipes(dir, recipe.except("activation"))

        expect(strategy_for(report_path).try_recipe_run).to be_nil
      end
    end

    it "does not replay a recipe that is not a hash" do
      Dir.mktmpdir do |dir|
        report_path = write_survivor_report(dir)
        write_recipes(dir, "activation")

        expect(strategy_for(report_path).try_recipe_run).to be_nil
      end
    end

    it "uses an empty location when the recipe omits it" do
      Dir.mktmpdir do |dir|
        report_path = write_survivor_report(dir)
        write_recipes(dir, recipe)

        expect(strategy_for(report_path).try_recipe_run.first.location).to eq({})
      end
    end

    it "preserves recipe method type and location metadata" do
      Dir.mktmpdir do |dir|
        report_path = write_survivor_report(dir)
        write_recipes(
          dir,
          recipe(
            "methodType" => "class",
            "location" => {
              "file" => "lib/sample.rb",
              "startLine" => 4,
              "endLine" => 4,
              "startCol" => 2,
              "endCol" => 7
            }
          )
        )

        mutant = strategy_for(report_path).try_recipe_run.first

        expect([mutant.subject.method_type, mutant.location]).to eq(
          [
            :class,
            {
              file: "lib/sample.rb",
              start_line: 4,
              end_line: 4,
              start_col: 2,
              end_col: 7
            }
          ]
        )
      end
    end

    it "does not warn when every cached survivor is matched" do
      Dir.mktmpdir do |dir|
        report_path = write_survivor_report(dir)
        write_recipes(dir, recipe)

        expect { strategy_for(report_path).try_recipe_run }.not_to output.to_stderr
      end
    end

    context "with a toplevel activation" do
      let(:toplevel_activation) do
        {
          "source" => "class Sample; def value = 2; end\n",
          "mode" => "toplevel",
          "file" => "lib/sample.rb",
          "line" => 1,
          "defOffset" => 0,
          "lexicalScope" => ["class Sample"],
          "owner" => "self",
          "singleton" => false
        }
      end

      it "replays a complete toplevel activation through the fast path", :aggregate_failures do
        Dir.mktmpdir do |dir|
          report_path = write_survivor_report(dir)
          write_recipes(dir, recipe("activation" => toplevel_activation))

          mutants = strategy_for(report_path).try_recipe_run

          expect(mutants.size).to eq(1)
          expect(mutants.first.precomputed_activation.lexical_scope).to eq(["class Sample"])
        end
      end

      it "does not replay a legacy toplevel activation without lexical scope" do
        Dir.mktmpdir do |dir|
          report_path = write_survivor_report(dir)
          legacy = toplevel_activation.except("lexicalScope", "singleton")
          write_recipes(dir, recipe("activation" => legacy))

          expect(strategy_for(report_path).try_recipe_run).to be_nil
        end
      end

      it "does not replay a toplevel activation whose owner is nil" do
        Dir.mktmpdir do |dir|
          report_path = write_survivor_report(dir)
          write_recipes(dir, recipe("activation" => toplevel_activation.merge("owner" => nil)))

          expect(strategy_for(report_path).try_recipe_run).to be_nil
        end
      end

      it "does not replay a toplevel activation whose lexical scope is nil" do
        Dir.mktmpdir do |dir|
          report_path = write_survivor_report(dir)
          write_recipes(dir, recipe("activation" => toplevel_activation.merge("lexicalScope" => nil)))

          expect(strategy_for(report_path).try_recipe_run).to be_nil
        end
      end

      it "does not replay a toplevel activation whose lexical scope holds a non-string opener" do
        Dir.mktmpdir do |dir|
          report_path = write_survivor_report(dir)
          write_recipes(dir, recipe("activation" => toplevel_activation.merge("lexicalScope" => [nil])))

          expect(strategy_for(report_path).try_recipe_run).to be_nil
        end
      end

      it "does not replay a toplevel activation whose singleton flag is not a boolean" do
        Dir.mktmpdir do |dir|
          report_path = write_survivor_report(dir)
          write_recipes(dir, recipe("activation" => toplevel_activation.merge("singleton" => "false")))

          expect(strategy_for(report_path).try_recipe_run).to be_nil
        end
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
