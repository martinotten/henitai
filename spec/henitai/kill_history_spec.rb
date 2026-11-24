# frozen_string_literal: true

require "spec_helper"

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
end
