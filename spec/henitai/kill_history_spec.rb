# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"

RSpec.describe Henitai::KillHistory do
  subject(:history) { described_class.new }

  def result(status, killing_tests)
    Henitai::ScenarioExecutionResult.new(status:, stdout: "", stderr: "", log_path: nil, killing_tests:)
  end

  it "counts each kill toward every test file that failed" do
    history.progress(:mutant, scenario_result: result(:killed, %w[/a_spec.rb /b_spec.rb]))
    history.progress(:mutant, scenario_result: result(:killed, %w[/a_spec.rb]))

    expect([history.fetch("/a_spec.rb"), history.fetch("/b_spec.rb")]).to eq([2, 1])
  end

  it "ignores verdicts other than killed" do
    %i[survived timeout runtime_error compile_error].each do |status|
      history.progress(:mutant, scenario_result: result(status, %w[/a_spec.rb]))
    end

    expect(history.fetch("/a_spec.rb", 0)).to eq(0)
  end

  it "ignores progress without a scenario result" do
    history.progress(:mutant)

    expect(history.fetch("/a_spec.rb", :none)).to eq(:none)
  end

  describe "hung files" do
    def mutant_for(expression)
      Struct.new(:subject).new(Struct.new(:expression).new(expression))
    end

    def timed_out(hanging_test)
      Henitai::ScenarioExecutionResult.new(
        status: :timeout, stdout: "", stderr: "", log_path: nil, hanging_test:
      )
    end

    it "remembers the file that hung for a mutant of the same subject" do
      history.progress(mutant_for("Foo#bar"), scenario_result: timed_out("/a_spec.rb"))

      expect(history.hung?(mutant_for("Foo#bar"), "/a_spec.rb")).to be(true)
    end

    it "does not mark the hung file for a mutant of another subject" do
      history.progress(mutant_for("Foo#bar"), scenario_result: timed_out("/a_spec.rb"))

      expect(history.hung?(mutant_for("Foo#baz"), "/a_spec.rb")).to be(false)
    end

    it "does not mark other files of the same subject" do
      history.progress(mutant_for("Foo#bar"), scenario_result: timed_out("/a_spec.rb"))

      expect(history.hung?(mutant_for("Foo#bar"), "/b_spec.rb")).to be(false)
    end

    it "compares the file by its expanded path" do
      history.progress(mutant_for("Foo#bar"), scenario_result: timed_out("spec/a_spec.rb"))

      expect(history.hung?(mutant_for("Foo#bar"), File.expand_path("spec/a_spec.rb"))).to be(true)
    end

    it "ignores timeouts without a hanging test" do
      history.progress(mutant_for("Foo#bar"), scenario_result: timed_out(nil))

      expect(history.hung?(mutant_for("Foo#bar"), nil)).to be(false)
    end

    it "ignores a hanging test on verdicts other than timeout" do
      killed = Henitai::ScenarioExecutionResult.new(
        status: :killed, stdout: "", stderr: "", log_path: nil, killing_tests: ["/a_spec.rb"]
      )
      history.progress(mutant_for("Foo#bar"), scenario_result: killed)

      expect(history.hung?(mutant_for("Foo#bar"), "/a_spec.rb")).to be(false)
    end

    it "treats a subject without an expression as unknown" do
      history.progress(Struct.new(:subject).new(nil), scenario_result: timed_out("/a_spec.rb"))

      expect(history.hung?(Struct.new(:subject).new(nil), "/a_spec.rb")).to be(false)
    end
  end

  describe "persisting the order" do
    def mutant_for(expression)
      Struct.new(:subject).new(Struct.new(:expression).new(expression))
    end

    def timed_out(hanging_test)
      Henitai::ScenarioExecutionResult.new(
        status: :timeout, stdout: "", stderr: "", log_path: nil, hanging_test:
      )
    end

    def killed_by(*killing_tests)
      result(:killed, killing_tests)
    end

    def write_order(path, payload)
      File.write(path, JSON.generate(payload))
    end

    it "keeps kills and hangs across a write and a load" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "order.json")
        history.progress(mutant_for("Foo#bar"), scenario_result: timed_out("#{dir}/b_spec.rb"))
        history.progress(:mutant, scenario_result: killed_by("#{dir}/a_spec.rb"))
        history.write(path)

        loaded = described_class.load(path)

        expect([loaded.fetch("#{dir}/a_spec.rb"), loaded.hung?(mutant_for("Foo#bar"), "#{dir}/b_spec.rb")])
          .to eq([1, true])
      end
    end

    it "expands relative paths from the file" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "order.json")
        write_order(path, { version: 1, kills: { "spec/a_spec.rb" => 3 }, hangs: { "Foo#bar" => ["spec/b_spec.rb"] } })

        loaded = described_class.load(path)

        expect([loaded.fetch(File.expand_path("spec/a_spec.rb")),
                loaded.hung?(mutant_for("Foo#bar"), File.expand_path("spec/b_spec.rb"))]).to eq([3, true])
      end
    end

    it "loads empty for a missing file" do
      Dir.mktmpdir do |dir|
        loaded = described_class.load(File.join(dir, "missing.json"))

        expect(loaded.fetch("/a_spec.rb", :none)).to eq(:none)
      end
    end

    it "loads empty for invalid JSON" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "order.json")
        File.write(path, "{not json")

        expect(described_class.load(path).fetch("/a_spec.rb", :none)).to eq(:none)
      end
    end

    it "loads empty for another version" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "order.json")
        write_order(path, { version: 2, kills: { "/a_spec.rb" => 3 }, hangs: {} })

        expect(described_class.load(path).fetch("/a_spec.rb", :none)).to eq(:none)
      end
    end

    it "replaces a file's loaded kills with the count of this run when it killed again" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "order.json")
        write_order(path, { version: 1, kills: { "/a_spec.rb" => 5 }, hangs: {} })
        run = described_class.load(path)
        run.progress(:mutant, scenario_result: killed_by("/a_spec.rb"))
        run.write(path)

        expect(JSON.parse(File.read(path))["kills"]).to eq("/a_spec.rb" => 1)
      end
    end

    it "keeps the loaded kills of files that did not kill in this run" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "order.json")
        write_order(path, { version: 1, kills: { "/a_spec.rb" => 5, "/b_spec.rb" => 2 }, hangs: {} })
        run = described_class.load(path)
        run.progress(:mutant, scenario_result: killed_by("/a_spec.rb"))
        run.write(path)

        expect(JSON.parse(File.read(path))["kills"]).to eq("/a_spec.rb" => 1, "/b_spec.rb" => 2)
      end
    end

    it "adds this run's kills to the loaded count while the run is going" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "order.json")
        write_order(path, { version: 1, kills: { "/a_spec.rb" => 5 }, hangs: {} })
        run = described_class.load(path)
        run.progress(:mutant, scenario_result: killed_by("/a_spec.rb"))

        expect(run.fetch("/a_spec.rb")).to eq(6)
      end
    end

    it "unions the loaded and the new hangs per subject" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "order.json")
        write_order(path, { version: 1, kills: {}, hangs: { "Foo#bar" => ["/b_spec.rb"] } })
        run = described_class.load(path)
        run.progress(mutant_for("Foo#bar"), scenario_result: timed_out("/a_spec.rb"))
        run.write(path)

        expect(JSON.parse(File.read(path))["hangs"]).to eq("Foo#bar" => ["/a_spec.rb", "/b_spec.rb"])
      end
    end

    it "stores paths inside the working directory relative to it" do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          path = File.join(dir, "order.json")
          run = described_class.new
          run.progress(mutant_for("Foo#bar"), scenario_result: timed_out(File.join(Dir.pwd, "spec/b_spec.rb")))
          run.progress(:mutant, scenario_result: killed_by(File.join(Dir.pwd, "spec/a_spec.rb")))
          run.write(path)

          stored = JSON.parse(File.read(path))
          expect([stored["kills"], stored["hangs"]])
            .to eq([{ "spec/a_spec.rb" => 1 }, { "Foo#bar" => ["spec/b_spec.rb"] }])
        end
      end
    end

    it "stores paths outside the working directory absolute" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "order.json")
        run = described_class.new
        run.progress(:mutant, scenario_result: killed_by("/elsewhere/a_spec.rb"))
        run.write(path)

        expect(JSON.parse(File.read(path))["kills"]).to eq("/elsewhere/a_spec.rb" => 1)
      end
    end

    it "creates the directory of the file" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "nested", "order.json")
        described_class.new.write(path)

        expect(JSON.parse(File.read(path))).to eq("version" => 1, "kills" => {}, "hangs" => {})
      end
    end
  end
end
