# frozen_string_literal: true

module SpecSupport
  module NodeSearchHelper
    def find_nodes(node, type, results = [])
      return results unless node.respond_to?(:type)

      results << node if node.type == type
      node.children.each { |child| find_nodes(child, type, results) }
      results
    end
  end
end
