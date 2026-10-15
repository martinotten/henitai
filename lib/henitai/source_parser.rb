# frozen_string_literal: true

require "parser/source/buffer"
require "prism"

module Henitai
  # Parses Ruby source into parser-compatible AST nodes using Prism.
  #
  # The parser translation layer keeps the `Parser::AST::Node` shape that the
  # mutation pipeline and Unparser already expect, while delegating syntax
  # support to Prism.
  class SourceParser
    DEFAULT_PATH = "(string)"

    # Emits the modern parser-gem AST format (procarg0, kwargs, index, lambda,
    # forward_arg, ...). The legacy format cannot tell `|x|` from `|x,|` or
    # keyword arguments from a braced hash, so re-rendering a mutated subtree
    # through the unparser would silently change its meaning.
    class Builder < Prism::Translation::Parser::Builder
      modernize
    end

    @cache = {}

    def self.parse(source, path: DEFAULT_PATH)
      new.parse(source, path:)
    end

    # Returns the parsed AST for +path+, re-using a cached result when the
    # file's mtime has not changed. This avoids parsing the same file twice
    # across pipeline phases (e.g. SubjectResolver then MutantGenerator).
    def self.parse_file(path)
      key = [path, File.mtime(path)]
      @cache[key] ||= new.parse_file(path)
    end

    # Clears the parse cache. Intended for test isolation.
    def self.clear_cache!
      @cache.clear
    end

    def parse(source, path: DEFAULT_PATH)
      Prism::Translation::ParserCurrent.new(Builder.new).parse(source_buffer(source, path))
    end

    # Read as UTF-8, Ruby's own default source encoding, not the process
    # locale: with LANG=C the default external encoding is US-ASCII and every
    # non-ASCII source file would fail to parse. A magic encoding comment is
    # still honoured by the parser buffer, which re-encodes to UTF-8.
    def parse_file(path)
      parse(File.read(path, encoding: Encoding::UTF_8), path:)
    end

    private

    def source_buffer(source, path)
      Parser::Source::Buffer.new(path).tap do |buffer|
        buffer.source = source
      end
    end
  end
end
