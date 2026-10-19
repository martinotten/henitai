# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::SignatureLine do
  def mutant_for(range, start_line)
    subject = Struct.new(:source_range).new(range)
    Struct.new(:subject, :location).new(subject, { start_line: })
  end

  it "is true when the mutant starts on the subject's first line" do
    expect(described_class.on?(mutant_for(5..9, 5))).to be(true)
  end

  it "is false for a body line" do
    expect(described_class.on?(mutant_for(5..9, 6))).to be(false)
  end

  it "is false for a subject without a source range" do
    expect(described_class.on?(mutant_for(nil, 5))).to be(false)
  end

  it "is false for an object without a subject" do
    expect(described_class.on?(Object.new)).to be(false)
  end
end
