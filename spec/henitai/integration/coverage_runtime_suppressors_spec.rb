# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Integration::CoverageRuntimeSuppressors do
  it "suppresses SimpleCov startup through its singleton class", :aggregate_failures do
    simplecov = Object.new
    allow(described_class).to receive(:require).with("simplecov")
    allow(Object).to receive(:const_get).with(:SimpleCov).and_return(simplecov)
    allow(simplecov.singleton_class).to receive(:prepend)

    described_class.suppress_simplecov!

    expect(described_class).to have_received(:require).with("simplecov")
    expect(simplecov.singleton_class).to have_received(:prepend)
      .with(Henitai::Integration::SimpleCovStartSuppressor)
  end

  it "suppresses Coverage startup through its singleton class", :aggregate_failures do
    coverage = Object.new
    allow(described_class).to receive(:require).with("coverage")
    allow(Object).to receive(:const_get).with(:Coverage).and_return(coverage)
    allow(coverage.singleton_class).to receive(:prepend)

    described_class.suppress_coverage!

    expect(described_class).to have_received(:require).with("coverage")
    expect(coverage.singleton_class).to have_received(:prepend)
      .with(Henitai::Integration::CoverageStartSuppressor)
  end
end
