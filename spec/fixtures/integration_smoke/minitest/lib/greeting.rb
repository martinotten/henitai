# frozen_string_literal: true

class Greeting
  def message
    "Hello"
  end

  # henitai:disable
  def shout
    "HELLO"
  end

  def whisper
    "hello" # henitai:disable
  end

  def cheer
    1 + 1 # henitai:disable ArithmeticOperator: smoke per-operator
  end
end
