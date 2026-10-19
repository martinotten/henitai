# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::Integration::Rspec do
  let(:repo_gemfile) { File.expand_path("../../../Gemfile", __dir__) }

  it "writes the killing spec file, and only it, as failed_tests in the child report" do
    Dir.mktmpdir do |dir|
      source = write(dir, "lib/sample.rb", "class Sample\n  def self.sum(a, b)\n    a + b\n  end\nend\n")
      killing = write(dir, "spec/killing_spec.rb", spec_source("expect(Sample.sum(3, 1)).to eq(4)"))
      passing = write(dir, "spec/passing_spec.rb", spec_source("expect(1).to eq(1)"))

      stdout, stderr, status = run_child(dir, source, [killing, passing])

      report = JSON.parse(File.read(Dir.glob(File.join(dir, "reports/mutation-logs/*.report.json")).first))
      expect([status.success?, report.fetch("failed_tests"), JSON.parse(stdout)]).to eq(
        [true, [File.expand_path(killing)], [File.expand_path(killing)]]
      ), [stdout, stderr].reject(&:empty?).join("\n")
    end
  end

  it "attributes an after(:context) hook failure to its spec file" do
    Dir.mktmpdir do |dir|
      source = write(dir, "lib/sample.rb", "class Sample\n  def self.sum(a, b)\n    a + b\n  end\nend\n")
      hooked = write(dir, "spec/hooked_spec.rb", hook_spec_source("after(:context) { raise \"cleanup\" }"))
      passing = write(dir, "spec/passing_spec.rb", spec_source("expect(1).to eq(1)"))

      _stdout, stderr, = run_child(dir, source, [hooked, passing])

      expect(child_report(dir).fetch("failed_tests")).to eq([File.expand_path(hooked)]), stderr
    end
  end

  it "flags a failure outside any spec file as unattributed" do
    Dir.mktmpdir do |dir|
      source = write(dir, "lib/sample.rb", "class Sample\n  def self.sum(a, b)\n    a + b\n  end\nend\n")
      suite_hook = write(dir, "spec/suite_hook_spec.rb", suite_hook_spec_source)

      _stdout, stderr, = run_child(dir, source, [suite_hook])

      report = child_report(dir)
      expect([report.fetch("failed_tests"), report.fetch("unattributed_failures")]).to eq([[], true]), stderr
    end
  end

  def child_report(dir)
    JSON.parse(File.read(Dir.glob(File.join(dir, "reports/mutation-logs/*.report.json")).first))
  end

  def hook_spec_source(hook)
    <<~RUBY
      RSpec.describe "hooked" do
        #{hook}
        it("works") { expect(1).to eq(1) }
      end
    RUBY
  end

  def suite_hook_spec_source
    <<~RUBY
      RSpec.configure { |config| config.after(:suite) { raise "suite cleanup" } }
      RSpec.describe "suite hook" do
        it("works") { expect(1).to eq(1) }
      end
    RUBY
  end

  def write(dir, relative, source)
    path = File.join(dir, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, source)
    path
  end

  def spec_source(expectation)
    <<~RUBY
      require_relative "../lib/sample"

      RSpec.describe "example" do
        it("works") { #{expectation} }
      end
    RUBY
  end

  def run_child(dir, source, spec_paths)
    script = <<~RUBY
      require "henitai"
      require #{source.dump}
      subject = Henitai::SubjectResolver.new.resolve_from_files([#{source.dump}]).first
      mutant = Henitai::MutantGenerator.new.generate([subject], [Henitai::Operators::ArithmeticOperator.new]).first
      result = Henitai::Integration::Rspec.new.run_mutant(mutant: mutant, test_files: #{spec_paths.inspect}, timeout: 20.0)
      abort(result.status.to_s) unless result.status == :killed
      puts JSON.generate(result.killing_tests)
    RUBY
    Open3.capture3({ "BUNDLE_GEMFILE" => repo_gemfile }, "bundle", "exec", "ruby", "-rjson", "-e", script, chdir: dir)
  end
end
