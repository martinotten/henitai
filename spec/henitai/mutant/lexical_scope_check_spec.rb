# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Mutant::LexicalScopeCheck do
  describe ".resolves?" do
    it "accepts empty openers" do
      expect(described_class.resolves?([])).to be(true)
    end

    it "accepts an existing module opener" do
      stub_const("LscOuter", Module.new)

      expect(described_class.resolves?(["module LscOuter"])).to be(true)
    end

    it "rejects a missing module opener" do
      expect(described_class.resolves?(["module LscMissing"])).to be(false)
    end

    it "rejects a constant that is not a class for a class opener" do
      stub_const("LscOuter", Module.new)

      expect(described_class.resolves?(["class LscOuter"])).to be(false)
    end

    it "accepts an existing class for a class opener" do
      stub_const("LscKlass", Class.new)

      expect(described_class.resolves?(["class LscKlass"])).to be(true)
    end

    it "rejects a module opener for an existing class, as Ruby raises a TypeError there" do
      stub_const("LscKlass", Class.new)

      expect(described_class.resolves?(["module LscKlass"])).to be(false)
    end

    it "accepts a self-prefixed opener that names a constant of the enclosing scope" do
      stub_const("LscOuter", Module.new)
      stub_const("LscOuter::Inner", Class.new)

      expect(described_class.resolves?(["module LscOuter", "class self::Inner"])).to be(true)
    end

    it "rejects a self-prefixed opener whose constant is missing" do
      stub_const("LscOuter", Module.new)

      expect(described_class.resolves?(["module LscOuter", "class self::Missing"])).to be(false)
    end

    it "accepts a class_eval opener on a self-prefixed constant" do
      stub_const("LscOuter", Module.new)
      stub_const("LscOuter::Point", Class.new)

      expect(described_class.resolves?(["module LscOuter", "self::Point.class_eval do"])).to be(true)
    end

    it "accepts a top-level prefixed opener" do
      stub_const("LscTop", Class.new)

      expect(described_class.resolves?(["class ::LscTop"])).to be(true)
    end

    it "resolves nested openers through their parents" do
      stub_const("LscOuter", Module.new)
      stub_const("LscOuter::Inner", Class.new)

      expect(described_class.resolves?(["module LscOuter", "class Inner"])).to be(true)
    end

    it "rejects a nested opener whose class is undefined and does not create it", :aggregate_failures do
      stub_const("LscOuter", Module.new)

      expect(described_class.resolves?(["module LscOuter", "class Inner"])).to be(false)
      expect(LscOuter.const_defined?(:Inner, false)).to be(false)
    end

    it "rejects a qualified opener whose parent is undefined" do
      expect(described_class.resolves?(["class LscMissing::Inner"])).to be(false)
    end

    it "resolves the first segment of a qualified opener lexically" do
      stub_const("LscOuter", Module.new)
      stub_const("LscOuter::Ns", Module.new)
      stub_const("LscOuter::Ns::Leaf", Class.new)

      expect(described_class.resolves?(["module LscOuter", "class Ns::Leaf"])).to be(true)
    end

    it "does not resolve a nested opener to a top-level constant" do
      stub_const("LscOuter", Module.new)
      stub_const("LscShared", Module.new)

      expect(described_class.resolves?(["module LscOuter", "module LscShared"])).to be(false)
    end

    it "stops at a singleton opener and accepts it" do
      expect(described_class.resolves?(["class << LscSingletonMissing"])).to be(true)
    end

    it "checks the openers before a singleton opener", :aggregate_failures do
      stub_const("LscOuter", Module.new)

      expect(described_class.resolves?(["module LscOuter", "class << self"])).to be(true)
      expect(described_class.resolves?(["module LscMissing", "class << self"])).to be(false)
    end
  end
end
