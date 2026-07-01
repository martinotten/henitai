# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Reporter do
  describe ".reporter_class" do
    {
      "terminal" => Henitai::Reporter::Terminal,
      "json" => Henitai::Reporter::Json,
      "html" => Henitai::Reporter::Html,
      "dashboard" => Henitai::Reporter::Dashboard
    }.each do |name, klass|
      it "resolves #{name.inspect} to #{klass}" do
        expect(described_class.reporter_class(name)).to eq(klass)
      end
    end

    it "raises ArgumentError for an unknown reporter name" do
      expect { described_class.reporter_class("nope") }
        .to raise_error(ArgumentError, /Unknown reporter: nope\. Valid reporters: terminal, json, html, dashboard/)
    end
  end

  describe ".run_all" do
    it "builds and reports through each named reporter with the shared config and history store" do
      result = instance_double(Henitai::Result)
      config = instance_double(Henitai::Configuration)
      history_store = instance_double(Henitai::MutantHistoryStore)
      reporter = instance_double(Henitai::Reporter::Terminal)

      allow(Henitai::Reporter::Terminal).to receive(:new).with(config:, history_store:).and_return(reporter)
      allow(reporter).to receive(:report)

      described_class.run_all(names: ["terminal"], result:, config:, history_store:)

      expect(reporter).to have_received(:report).with(result)
    end

    it "raises ArgumentError when any configured name is unknown" do
      result = instance_double(Henitai::Result)
      config = instance_double(Henitai::Configuration)

      expect { described_class.run_all(names: ["bogus"], result:, config:) }
        .to raise_error(ArgumentError, /Unknown reporter: bogus/)
    end
  end
end
