# frozen_string_literal: true

require_relative "warning_silencer"

Henitai::WarningSilencer.silence do
  require "parser/current"
end
