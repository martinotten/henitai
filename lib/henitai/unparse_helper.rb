# frozen_string_literal: true

require "unparser"

module Henitai
  # Shared safe unparse helpers for user-facing output and report serialization.
  module UnparseHelper
    private

    def safe_unparse(node)
      Unparser.unparse(node)
    rescue Unparser::UnknownNodeError, Unparser::InvalidNodeError,
           Unparser::UnsupportedNodeError, EncodingError
      # Unparser does not support all AST node types, and some mutated string
      # segments carry incompatible encodings; fall back gracefully for those.
      # Other failures (e.g. NoMethodError) are bugs and must surface.
      fallback_source(node)
    end

    def fallback_source(node)
      return "" if node.nil?
      return node.type.to_s if node.respond_to?(:type)

      node.class.name
    end
  end
end
