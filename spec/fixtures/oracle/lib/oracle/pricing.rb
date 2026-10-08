# frozen_string_literal: true

module Oracle
  # One method per construct; the comment names the review finding it covers.
  class Pricing < Base
    RATE = 3

    # ACT-01: own constant from a class method.
    def self.rate
      RATE + 1
    end

    # ACT-01: constant of the enclosing module.
    def net(amount)
      amount + TAX
    end

    # ACT-02: implicit super.
    def total(amount)
      super + 1
    end

    # ACT-02: yield.
    def each_tier
      yield RATE + 1
    end

    # ACT-02: block_given?.
    def maybe_double(amount)
      return amount * 2 unless block_given?

      yield amount
    end

    # GEN-01: keyword arguments in a call that a mutation re-renders.
    def tagged(amount)
      amount > 3 ? tag(name: "big", size: amount) : tag(name: "small", size: amount)
    end

    def tag(name:, size:)
      "#{name}:#{size}"
    end

    # GEN-01: one-parameter block inside a mutated expression.
    def firsts(pairs)
      pairs.map { |pair| pair.first }.sum + 1 # rubocop:disable Style/SymbolProc -- the block is the construct
    end

    # ACT-05: multibyte characters before the mutation site.
    def label(width)
      unit = "größe"
      width + 1 > 2 ? unit : "klein"
    end

    # GEN-02: negated binary condition.
    # rubocop:disable Style/IfWithBooleanLiteralBranches, Style/RedundantConditional -- the if is the construct
    def bulk?(count)
      if count > 3
        true
      else
        false
      end
    end
    # rubocop:enable Style/IfWithBooleanLiteralBranches, Style/RedundantConditional

    # GEN-03: elsif.
    def grade(score)
      if score > 90
        :a
      elsif score > 50
        :b
      else
        :c
      end
    end

    # ACT-08: mutation in a default value.
    def discounted(amount, discount = 1 + 1)
      amount - discount
    end

    # EXE-04: SystemExit raised by the code under test.
    def finish(done)
      return :ok if done

      exit(0)
    end

    # ACT-07: visibility.
    def masked(amount)
      secret + amount
    end

    private

    def secret
      10 + 1
    end
  end
end
