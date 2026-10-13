@testable import MantissaCore

/// Evaluates parsed syntax straight to a complex decimal with no simplification at all, as `NaiveEvaluator` does for real
/// numbers. Only arithmetic, powers, roots and the absolute value are supported; anything else is skipped by the caller.
///
/// A power is the principal value `e^(y ln z)`, except for the convention the exact layer shares with the real
/// calculator: an odd root of a negative real number is the real root (∛(−8) = −2).
struct NaiveComplexEvaluator {
  let precision = 100

  func evaluate(_ syntax: Syntax) throws(MathError) -> ComplexDecimal {
    let p = precision
    switch syntax {
    case .number(let value): return ComplexDecimal(real: BigDecimal(value, precision: p))
    case .symbol, .infinity: throw .notNumeric
    case .constant(let constant):
      switch constant {
      case .pi: return ComplexDecimal(real: BigDecimal.pi(precision: p))
      case .e: return ComplexDecimal(real: BigDecimal.e(precision: p))
      case .i: return ComplexDecimal(real: BigDecimal(0), imaginary: BigDecimal(1))
      case .infinity: throw .notNumeric
      }
    case .negate(let operand): return -(try evaluate(operand))
    case .binary(let op, let left, let right):
      let a = try evaluate(left)
      let b = try evaluate(right)
      switch op {
      case .add: return cleaned(a.adding(b, precision: p))
      case .subtract: return cleaned(a.adding(-b, precision: p))
      case .multiply: return cleaned(a.multiplied(by: b, precision: p))
      case .divide: return cleaned(try a.divided(by: b, precision: p))
      case .power:
        if case .number(let exponent) = right { return try power(a, b, rational: exponent) }
        return try power(a, b, rational: nil)
      }
    case .postfix: throw .notNumeric
    case .call(let function, let arguments):
      let values = try arguments.map { (argument: Syntax) throws(MathError) -> ComplexDecimal in try evaluate(argument)
      }
      switch function {
      case .abs: return ComplexDecimal(real: try values[0].magnitude(precision: p))
      case .sqrt:
        return try power(
          values[0], ComplexDecimal(real: BigDecimal(Rational(1, 2), precision: p)), rational: Rational(1, 2))
      case .cbrt:
        return try power(
          values[0], ComplexDecimal(real: BigDecimal(Rational(1, 3), precision: p)), rational: Rational(1, 3))
      default: throw .notNumeric
      }
    case .radical(let index, let radicand):
      let value = try evaluate(radicand)
      guard let index else {
        return try power(
          value, ComplexDecimal(real: BigDecimal(Rational(1, 2), precision: p)), rational: Rational(1, 2))
      }
      let n = try evaluate(index)
      let reciprocal = try ComplexDecimal(real: BigDecimal(1)).divided(by: n, precision: p)
      var rational: Rational?
      if case .number(let degree) = index, !degree.isZero { rational = degree.reciprocal }
      return try power(value, reciprocal, rational: rational)
    }
  }

  /// A component far below the other is the residue of rounding, not a value.
  private func cleaned(_ value: ComplexDecimal) -> ComplexDecimal {
    var result = value
    if let real = value.real.decimalOrder, let imaginary = value.imaginary.decimalOrder {
      if real < imaginary - precision + 12 { result.real = BigDecimal(0) }
      if imaginary < real - precision + 12 { result.imaginary = BigDecimal(0) }
    }
    return result
  }

  /// `rational` is the exponent as the exact fraction it was written as, when it was one: a decimal rounded to 100 digits
  /// no longer says whether the root is odd.
  private func power(
    _ base: ComplexDecimal, _ exponent: ComplexDecimal, rational: Rational?
  ) throws(MathError) -> ComplexDecimal {
    let p = precision
    if base.isZero {
      if exponent.isReal && exponent.real.signum > 0 { return ComplexDecimal(real: BigDecimal(0)) }
      throw exponent.isReal ? .divisionByZero : .domain
    }
    if exponent.isReal, let whole = exponent.real.asInt, whole.magnitude < 200 {
      return cleaned(try base.power(whole, precision: p))
    }
    if exponent.isReal && base.isReal && base.real.isNegative, let rational {
      if !rational.denominator.isEven {
        // The real root: ∛(−8) = −2, (−8)^(2/3) = 4.
        let magnitude = try base.real.magnitude.power(exponent.real, precision: p)
        return ComplexDecimal(real: rational.numerator.isEven ? magnitude : -magnitude)
      }
    }
    // The exponent is not magnified here: the generator keeps exponents small.
    let logarithm = try base.ln(precision: p + 10)
    return cleaned(try exponent.multiplied(by: logarithm, precision: p + 10).exp(precision: p))
  }
}

/// Random syntax for complex arithmetic: numbers, i, square roots of anything, and small powers.
struct ComplexSyntaxGenerator {
  var base: SyntaxGenerator

  init(seed: UInt64) { base = SyntaxGenerator(seed: seed) }

  mutating func leaf() -> Syntax {
    switch base.int(0...9) {
    case 0...2: return .constant(.i)
    case 3: return .number(Rational(base.int(1...5), base.int(2...5)))
    case 4: return .radical(index: nil, radicand: .number(Rational(-base.int(1...12))))
    default: return .number(Rational(base.int(0...6)))
    }
  }

  mutating func exponent() -> Syntax {
    switch base.int(0...9) {
    case 0, 1: return .number(Rational(2))
    case 2: return .number(Rational(-1))
    case 3: return .number(Rational(3))
    case 4: return .number(Rational(1, 2))
    case 5: return .number(Rational(1, 4))
    case 6: return .number(Rational(3, 2))
    case 7: return .number(Rational(-1, 2))
    case 8: return .number(Rational(1, 3))
    default: return .number(Rational(base.int(-4...5)))
    }
  }

  mutating func make(depth: Int) -> Syntax {
    if depth == 0 || base.int(0...3) == 0 { return leaf() }
    let child = depth - 1
    switch base.int(0...10) {
    case 0: return .negate(make(depth: child))
    case 1, 2: return .binary(.add, make(depth: child), make(depth: child))
    case 3: return .binary(.subtract, make(depth: child), make(depth: child))
    case 4, 5: return .binary(.multiply, make(depth: child), make(depth: child))
    case 6: return .binary(.divide, make(depth: child), make(depth: child))
    case 7, 8: return .binary(.power, make(depth: child), exponent())
    case 9: return .radical(index: nil, radicand: make(depth: child))
    default: return .call(.abs, [make(depth: child)])
    }
  }
}
