# frozen_string_literal: true

# Reporter integration examples naturally use a compact fixture helper and
# multiple assertions against the produced artifacts.
# rubocop:disable Metrics/MethodLength, RSpec/MultipleExpectations, RSpec/ExampleLength

require "fileutils"
require "json"
require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::Reporter::Json do
  def build_config(reports_dir:)
    Struct.new(:reports_dir).new(reports_dir)
  end

  def build_result(schema:)
    Struct.new(:to_stryker_schema).new(schema)
  end

  def build_history_mutant
    subject = Henitai::Subject.new(namespace: "Sample", method_name: "value")
    mutant = Struct.new(
      :subject,
      :operator,
      :description,
      :location,
      :status,
      :mutated_node
    ) do
      def killed?
        status == :killed
      end

      def survived?
        status == :survived
      end

      def equivalent?
        status == :equivalent
      end
    end

    mutant.new(
      subject,
      "ArithmeticOperator",
      "replaced + with -",
      {
        file: "lib/sample.rb",
        start_line: 2,
        end_line: 2,
        start_col: 0,
        end_col: 5
      },
      :survived,
      Parser::CurrentRuby.parse("1 - 0")
    )
  end

  def build_history_result
    Struct.new(:mutants, :scoring_summary).new(
      [build_history_mutant],
      {
        mutation_score: 80.0,
        mutation_score_indicator: 40.0,
        equivalence_uncertainty: "~10-15% of live mutants"
      }
    )
  end

  it "writes mutation-report.json to the configured reports directory" do
    Dir.mktmpdir do |dir|
      reports_dir = File.join(dir, "nested", "reports")
      schema = {
        schemaVersion: "1.0",
        thresholds: { high: 80, low: 60 },
        files: {}
      }

      described_class.new(config: build_config(reports_dir:)).report(build_result(schema:))

      report_path = File.join(reports_dir, "mutation-report.json")

      expect(File).to exist(report_path)
    end
  end

  it "writes the schema payload as JSON" do
    Dir.mktmpdir do |dir|
      reports_dir = File.join(dir, "nested", "reports")
      schema = {
        schemaVersion: "1.0",
        thresholds: { high: 80, low: 60 },
        files: {}
      }

      described_class.new(config: build_config(reports_dir:)).report(build_result(schema:))

      report_path = File.join(reports_dir, "mutation-report.json")

      expect(JSON.parse(File.read(report_path), symbolize_names: true)).to eq(schema)
    end
  end

  it "writes an immutable session snapshot under sessions/<sessionId>/" do
    Dir.mktmpdir do |dir|
      reports_dir = File.join(dir, "reports")
      schema = {
        schemaVersion: "1.0",
        sessionId: "abc-123",
        thresholds: { high: 80, low: 60 },
        files: {}
      }

      described_class.new(config: build_config(reports_dir:)).report(build_result(schema:))

      snapshot = File.join(reports_dir, "sessions", "abc-123", "mutation-report.json")
      expect(File).to exist(snapshot)
      expect(JSON.parse(File.read(snapshot), symbolize_names: true)).to eq(schema)
    end
  end

  it "does not create a sessions directory when sessionId is absent" do
    Dir.mktmpdir do |dir|
      reports_dir = File.join(dir, "reports")
      schema = { schemaVersion: "1.0", thresholds: { high: 80, low: 60 }, files: {} }

      described_class.new(config: build_config(reports_dir:)).report(build_result(schema:))

      expect(Dir).not_to exist(File.join(reports_dir, "sessions"))
    end
  end

  it "writes activation-recipes.json to the session directory for survived mutants" do
    Dir.mktmpdir do |dir|
      reports_dir = File.join(dir, "reports")
      session_id  = "sess-xyz"

      survived = instance_double(
        Henitai::Mutant,
        survived?: true,
        stable_id: "stable-abc",
        subject: instance_double(
          Henitai::Subject,
          namespace: "Foo",
          method_name: "bar",
          method_type: :instance,
          source_file: "lib/foo.rb"
        ),
        operator: "ArithmeticOperator",
        description: "+ to -",
        location: { file: "lib/foo.rb", start_line: 1, end_line: 1, start_col: 0, end_col: 5 },
        covered_by: []
      )
      allow(Henitai::Mutant::Activator)
        .to receive(:activation_source_for).with(survived)
        .and_return("define_method(:bar) do\n  nil\nend\n")

      result = Struct.new(:to_stryker_schema, :session_id, :mutants).new(
        {
          schemaVersion: "1.0",
          sessionId: session_id,
          thresholds: { high: 80, low: 60 },
          files: {}
        },
        session_id,
        [survived]
      )

      described_class.new(config: build_config(reports_dir:)).report(result)

      recipe_path = File.join(
        reports_dir, "sessions", session_id,
        Henitai::SurvivorActivationCache::FILENAME
      )
      expect(File).to exist(recipe_path)
      recipes = JSON.parse(File.read(recipe_path))
      expect(recipes["stable-abc"]["activationSource"]).to eq("define_method(:bar) do\n  nil\nend\n")
    end
  end

  it "does not create an activation-recipes.json when there are no survivors" do
    Dir.mktmpdir do |dir|
      reports_dir = File.join(dir, "reports")
      session_id  = "sess-no-survivors"

      result = Struct.new(:to_stryker_schema, :session_id, :mutants).new(
        {
          schemaVersion: "1.0",
          sessionId: session_id,
          thresholds: { high: 80, low: 60 },
          files: {}
        },
        session_id,
        []
      )

      described_class.new(config: build_config(reports_dir:)).report(result)

      recipe_path = File.join(
        reports_dir, "sessions", session_id,
        Henitai::SurvivorActivationCache::FILENAME
      )
      expect(File).not_to exist(recipe_path)
    end
  end

  it "writes mutation-history.json from an injected history store" do
    Dir.mktmpdir do |dir|
      reports_dir = File.join(dir, "nested", "reports")
      store_path = File.join(reports_dir, "mutation-history.sqlite3")
      FileUtils.mkdir_p(reports_dir)
      File.write(store_path, "")
      store = instance_double(
        Henitai::MutantHistoryStore,
        path: store_path,
        trend_report: { runs: [{ version: "9.9.9" }], mutants: [] }
      )
      schema = { schemaVersion: "1.0", thresholds: { high: 80, low: 60 }, files: {} }

      described_class
        .new(config: build_config(reports_dir:), history_store: store)
        .report(build_result(schema:))

      history = JSON.parse(File.read(File.join(reports_dir, "mutation-history.json")), symbolize_names: true)
      expect(history[:runs].first).to include(version: "9.9.9")
    end
  end

  it "skips mutation-history.json when the injected store has no database file" do
    Dir.mktmpdir do |dir|
      reports_dir = File.join(dir, "reports")
      store = instance_double(
        Henitai::MutantHistoryStore,
        path: File.join(reports_dir, "missing.sqlite3")
      )
      schema = { schemaVersion: "1.0", thresholds: { high: 80, low: 60 }, files: {} }

      described_class
        .new(config: build_config(reports_dir:), history_store: store)
        .report(build_result(schema:))

      expect(File).not_to exist(File.join(reports_dir, "mutation-history.json"))
    end
  end

  it "writes mutation-history.json from the sqlite history store" do
    Dir.mktmpdir do |dir|
      reports_dir = File.join(dir, "nested", "reports")
      store = Henitai::MutantHistoryStore.new(
        path: File.join(reports_dir, "mutation-history.sqlite3")
      )
      store.record(
        build_history_result,
        version: "1.0.0",
        recorded_at: Time.utc(2026, 1, 1, 12, 0, 0)
      )

      schema = {
        schemaVersion: "1.0",
        thresholds: { high: 80, low: 60 },
        files: {}
      }

      described_class.new(config: build_config(reports_dir:)).report(build_result(schema:))

      report_path = File.join(reports_dir, "mutation-history.json")
      history = JSON.parse(File.read(report_path), symbolize_names: true)

      expect(history[:runs].first).to include(
        version: "1.0.0",
        mutationScore: 80.0
      )
      expect(history[:mutants].first).to include(
        currentStatus: "survived",
        daysAlive: 0
      )
    end
  end
end
# rubocop:enable Metrics/MethodLength, RSpec/MultipleExpectations, RSpec/ExampleLength
