@testable import MantissaCore

/// Builds random syntax trees from numbers, π, e and the operators and functions the parser knows. Domain errors are
/// common (a negative square root, ln of zero) and expected; the tests skip those.
struct SyntaxGenerator {
  var random: SplitMix64
  /// Whether `x` may appear as a leaf, for tests that evaluate at chosen values.
  var includesUnknown = false
  /// Whether `mod`, `min`, `max`, `sign`, the inverse reciprocals and the hyperbolic reciprocals may appear. Off by default,
  /// so that the random sequences of the older tests stay as they were.
  var includesDerivedFunctions = false
  /// Whether π may appear next to `x`, so that sums such as `x + π/2` occur inside the trigonometric functions.
  var includesPiWithUnknown = false

  init(seed: UInt64) { random = SplitMix64(seed: seed) }

  mutating func int(_ range: ClosedRange<Int>) -> Int {
    Int(random.next() % UInt64(range.count)) + range.lowerBound
  }

  mutating func leaf() -> Syntax {
    switch int(0...9) {
    case 0...3: return .number(Rational(int(0...12)))
    case 4: return .number(Rational(decimal: ["0.5", "2.25", "0.1", "1.5", "3.75", "0.125"][int(0...5)])!)
    case 5:
      if includesUnknown && includesPiWithUnknown && int(0...1) == 0 { return .constant(.pi) }
      return includesUnknown ? .symbol("x") : .constant(.pi)
    case 6: return .constant(.e)
    case 7: return .number(Rational(int(1...5), int(2...7)))
    default: return includesUnknown && int(0...1) == 0 ? .symbol("x") : .number(Rational(int(1...30)))
    }
  }

  /// A number in [-1, 1], so inverse sine and cosine are usually in range.
  mutating func unitInterval() -> Syntax {
    .number(Rational(int(-8...8), 8))
  }

  mutating func exponent() -> Syntax {
    switch int(0...7) {
    case 0: return .number(Rational(-1))
    case 1: return .number(Rational(2))
    case 2: return .number(Rational(3))
    case 3: return .number(Rational(1, 2))
    case 4: return .number(Rational(1, 3))
    case 5: return .number(Rational(2, 3))
    case 6: return .number(Rational(3, 2))
    default: return .number(Rational(int(-3...4)))
    }
  }

  mutating func make(depth: Int) -> Syntax {
    if depth == 0 || int(0...3) == 0 { return leaf() }
    let child = depth - 1
    switch int(0...(includesDerivedFunctions ? 20 : 16)) {
    case 0: return .negate(make(depth: child))
    case 1, 2: return .binary(.add, make(depth: child), make(depth: child))
    case 3: return .binary(.subtract, make(depth: child), make(depth: child))
    case 4, 5: return .binary(.multiply, make(depth: child), make(depth: child))
    case 6: return .binary(.divide, make(depth: child), make(depth: child))
    case 7: return .binary(.power, make(depth: child), exponent())
    case 8: return .radical(index: nil, radicand: make(depth: child))
    case 9: return .call(.sqrt, [make(depth: child)])
    case 10: return .call([.sin, .cos, .tan, .cot, .sec, .csc][int(0...5)], [make(depth: child)])
    case 11: return .call([.asin, .acos, .atan][int(0...2)], [unitInterval()])
    case 12: return .call([.ln, .abs, .exp][int(0...2)], [make(depth: child)])
    case 13: return .call(.log, [make(depth: child)])
    case 14: return .postfix(.factorial, .number(Rational(int(0...8))))
    case 15: return .call([.sinh, .cosh, .tanh, .atan][int(0...3)], [make(depth: child)])
    case 17: return .call([.mod, .min, .max][int(0...2)], [make(depth: child), make(depth: child)])
    case 18: return .call(.sign, [make(depth: child)])
    case 19: return .call([.acot, .asec, .acsc][int(0...2)], [make(depth: child)])
    case 20:
      return .call([.coth, .sech, .csch, .acoth, .asech, .acsch][int(0...5)], [make(depth: child)])
    default: return .call(.root, [make(depth: child), .number(Rational(int(2...4)))])
    }
  }
}
