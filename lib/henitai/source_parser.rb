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

    def self.parse(source, path: DEFAULT_PATH)
      new.parse(source, path:)
    end

    def self.parse_file(path)
      new.parse_file(path)
    end

    def parse(source, path: DEFAULT_PATH)
      Prism::Translation::ParserCurrent.new.parse(source_buffer(source, path))
    end

    def parse_file(path)
      # Ruby's file encoding rules apply here. Projects that use explicit source
      # encoding comments can be handled by a future encoding-aware option.
      parse(File.read(path), path:)
    end

    private

    def source_buffer(source, path)
      Parser::Source::Buffer.new(path).tap do |buffer|
        buffer.source = source
      end
    end
  end
end
