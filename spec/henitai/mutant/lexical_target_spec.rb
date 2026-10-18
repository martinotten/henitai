# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::Mutant::LexicalTarget do
  def subject_for(namespace, source_file: nil)
    Henitai::Subject.new(namespace:, method_name: "value",
                         source_location: source_file && { file: source_file, range: nil })
  end

  def activation(scope, owner: "self", singleton: false)
    Henitai::Mutant::Activation.new(source: "", mode: :toplevel, file: "lt.rb", line: 1, def_offset: 0,
                                    lexical_scope: scope, owner:, singleton:)
  end

  def write_source(dir, source)
    File.join(dir, "lexical_target_sample.rb").tap { |path| File.write(path, source) }
  end

  describe ".resolve" do
    it "returns the reopened class for an instance def" do
      stub_const("LtHost", Class.new)

      expect(described_class.resolve(subject_for("LtHost"), activation(["class LtHost"]))).to equal(LtHost)
    end

    it "returns the singleton class for a defs" do
      stub_const("LtHost", Class.new)

      result = described_class.resolve(subject_for("LtHost"), activation(["class LtHost"], singleton: true))

      expect(result).to equal(LtHost.singleton_class)
    end

    it "evaluates the owner expression inside the openers" do
      stub_const("LtOuter", Module.new)
      stub_const("LtOuter::Other", Class.new)

      result = described_class.resolve(subject_for("LtOuter"), activation(["module LtOuter"], owner: "Other"))

      expect(result).to equal(LtOuter::Other)
    end

    it "resolves a top-level def on a constant without openers" do
      stub_const("LtHost", Class.new)

      result = described_class.resolve(subject_for("LtHost"), activation([], owner: "LtHost", singleton: true))

      expect(result).to equal(LtHost.singleton_class)
    end

    it "loads the subject's source file when its class is not defined yet" do
      Dir.mktmpdir do |dir|
        path = write_source(dir, "class LtLoaded; end\n")
        hide_const("LtLoaded")

        result = described_class.resolve(subject_for("LtLoaded", source_file: path), activation(["class LtLoaded"]))

        expect(result.name).to eq("LtLoaded")
      ensure
        Object.class_eval { remove_const(:LtLoaded) if const_defined?(:LtLoaded, false) }
      end
    end

    it "loads the subject's source file when a singleton opener's receiver is not defined yet" do
      Dir.mktmpdir do |dir|
        path = write_source(dir, "class LtSingletonHost; end\nclass << LtSingletonHost; end\n")
        hide_const("LtSingletonHost")

        result = described_class.resolve(subject_for("LtSingletonHost", source_file: path),
                                         activation(["class << LtSingletonHost"]))

        expect(result).to equal(LtSingletonHost.singleton_class)
      ensure
        Object.class_eval { remove_const(:LtSingletonHost) if const_defined?(:LtSingletonHost, false) }
      end
    end

    it "refuses to create a phantom class when the subject's source fails to define it", :aggregate_failures do
      stub_const("LtOuter", Module.new)
      Dir.mktmpdir do |dir|
        path = write_source(dir, "module LtOuter; class Inner < LtMissingBase; end; end\n")
        subject = subject_for("LtOuter::Inner", source_file: path)

        expect { described_class.resolve(subject, activation(["module LtOuter", "class Inner"])) }
          .to raise_error(described_class::SubjectNotLoadedError, /LtMissingBase/)
        expect(LtOuter.const_defined?(:Inner, false)).to be(false)
      end
    end

    it "fails the activation when a top-level subject's source has a syntax error" do
      Dir.mktmpdir do |dir|
        path = write_source(dir, "class LtBroken\n  def value(\nend\n")
        subject = subject_for("LtBroken", source_file: path)

        expect { described_class.resolve(subject, activation([], owner: "LtBroken")) }
          .to raise_error(described_class::SubjectNotLoadedError, /failed to load/)
      end
    end

    it "names the namespace and the load error when a top-level subject's source raises" do
      Dir.mktmpdir do |dir|
        path = write_source(dir, "raise \"lt boom\"\n")
        subject = subject_for("LtRaising", source_file: path)

        expect { described_class.resolve(subject, activation([], owner: "LtRaising")) }
          .to raise_error(described_class::SubjectNotLoadedError,
                          "cannot activate LtRaising: its source failed to load (lt boom)")
      end
    end

    it "fails the activation when the loaded source still does not define the scope" do
      Dir.mktmpdir do |dir|
        path = write_source(dir, "# defines nothing\n")
        subject = subject_for("LtAbsent", source_file: path)

        expect { described_class.resolve(subject, activation(["class LtAbsent"])) }
          .to raise_error(described_class::SubjectNotLoadedError,
                          "cannot activate LtAbsent#value: its source did not define LtAbsent")
      end
    end

    it "leaves an undefined top-level owner to fail as a NameError after loading the source" do
      Dir.mktmpdir do |dir|
        path = write_source(dir, "# defines nothing\n")
        subject = subject_for("LtAbsentTop", source_file: path)

        expect { described_class.resolve(subject, activation([], owner: "LtAbsentTop")) }
          .to raise_error(NameError, /LtAbsentTop/)
      end
    end
  end

  describe ".load_target" do
    it "returns the subject's namespace constant" do
      stub_const("LtHost", Class.new)

      expect(described_class.load_target(subject_for("LtHost"))).to equal(LtHost)
    end

    it "loads the source file when the namespace constant is missing" do
      Dir.mktmpdir do |dir|
        path = write_source(dir, "module LtLoadedModule; end\n")

        expect(described_class.load_target(subject_for("LtLoadedModule", source_file: path)).name)
          .to eq("LtLoadedModule")
      ensure
        Object.class_eval { remove_const(:LtLoadedModule) if const_defined?(:LtLoadedModule, false) }
      end
    end

    it "returns a top-level prefixed namespace constant" do
      stub_const("LtHost", Class.new)

      expect(described_class.load_target(subject_for("::LtHost"))).to equal(LtHost)
    end

    it "raises the missing constant when the subject has neither a source file nor an AST" do
      expect { described_class.load_target(subject_for("LtNowhere")) }
        .to raise_error(NameError, /uninitialized constant LtNowhere/)
    end
  end
end
