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

  def strategy_for(report_path)
    config = Struct.new(:includes).new(["lib"])
    described_class.new(survivors_from: report_path, config:)
  end

  describe "#active?" do
    it "is active when a survivor report is configured" do
      strategy = described_class.new(
        survivors_from: "reports/mutation-report.json",
        config: nil
      )

      expect(strategy).to be_active
    end

    it "is inactive without a survivor report" do
      strategy = described_class.new(
        survivors_from: nil,
        config: nil
      )

      expect(strategy).not_to be_active
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
