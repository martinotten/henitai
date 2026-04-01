# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Reporter::Terminal do
  def build_mutant(status)
    Struct.new(:status).new(status)
  end

  def build_config
    Struct.new(:thresholds).new({})
  end

  it "prints progress glyphs for known statuses" do
    reporter = described_class.new(config: build_config)
    mutants = %i[killed survived timeout ignored].map { |status| build_mutant(status) }

    expect { mutants.each { |mutant| reporter.progress(mutant) } }
      .to output("·STI").to_stdout
  end

  it "does not print a glyph for unknown statuses" do
    reporter = described_class.new(config: build_config)

    expect { reporter.progress(build_mutant(:pending)) }.not_to output.to_stdout
  end
end
