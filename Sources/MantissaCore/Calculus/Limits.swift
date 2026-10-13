// Limits.
//
// A limit is first tried by substitution, which is the answer wherever the expression is continuous. Otherwise (an
// indeterminate form such as 0/0, a pole, a limit at infinity) the expression is evaluated at points that close in on the target
// — 10⁻⁸, 10⁻¹⁴, 10⁻²⁰, 10⁻³⁰ away, or 10⁶, 10¹², 10²⁴, 10⁴⁸ out — at several hundred digits, so that cancellation does not
// matter. A sequence that settles has its value recognised (a fraction, or a fraction of π, e, ln 2, √2, …); one that grows
// without bound is ±∞; the two sides of a finite point must agree; anything else is reported as not worked out.

enum LimitPoint {
  case finite(Expr)
  case plusInfinity
  case minusInfinity
}

enum LimitSide {
  case both, left, right
}

extension Expr {
  /// The limit of the expression as `variable` approaches `point`.
  func limit(_ variable: String, to point: LimitPoint, side: LimitSide = .both) throws(MathError) -> Expr {
    try LimitEngine(expression: self, variable: variable).limit(to: point, side: side)
  }

  static var infinity: Expr { .constant(.infinity) }
}

private struct LimitEngine {
  let expression: Expr
  let variable: String

  /// How a sequence of values behaves.
  private enum Behaviour {
    case settles(BigDecimal, error: BigDecimal)
    case grows(negative: Bool)
    case unclear
  }

  func limit(to point: LimitPoint, side: LimitSide) throws(MathError) -> Expr {
    if case .finite(let a) = point, let direct = substitution(at: a) { return direct }
    guard expression.freeSymbols.isSubset(of: [variable]) else { throw .unsupported }

    switch point {
    case .finite(let a):
      guard let target = Self.decimal(a) else { throw .unsupported }
      let sides: [LimitSide] = side == .both ? [.left, .right] : [side]
      var results: [Behaviour] = []
      for side in sides {
        // A side where the expression is not defined at all does not count (√x at 0 is a limit from the right).
        guard
          let values = sequence(
            side == .right ? [-8, -14, -20, -30] : [-8, -14, -20, -30], from: target, direction: side == .right ? 1 : -1
          )
        else { continue }
        results.append(behaviour(of: values))
      }
      guard !results.isEmpty else { throw .domain }
      return try combine(results)

    case .plusInfinity, .minusInfinity:
      let sign = { if case .plusInfinity = point { return 1 } else { return -1 } }()
      // Farther out where the expression allows it; e^(−x²) overflows beyond x of about 3·10⁴, so there are nearer lists too.
      for scales in [[6, 12, 24, 48], [3, 5, 7, 8], [1, 2, 3, 4]] {
        guard let values = sequence(scales, from: BigDecimal(0), direction: sign, scaleIsOutward: true) else {
          continue
        }
        return try combine([behaviour(of: values)])
      }
      throw .unsupported
    }
  }

  // MARK: Substitution

  /// The value at `a` when the expression is continuous there: defined, real, and made of continuous parts.
  private func substitution(at a: Expr) -> Expr? {
    let discontinuous = expression.collectAll(where: { part in
      if case .function(let function, _) = part { return [.floor, .ceil, .round].contains(function) }
      return false
    })
    guard discontinuous.isEmpty, let value = expression.substituting(variable, with: a), !value.containsInfinity else {
      return nil
    }
    // A square root of a negative number at the point means the real limit is not this complex value.
    if value.containsImaginaryUnit && !expression.containsImaginaryUnit && !a.containsImaginaryUnit { return nil }
    return value
  }

  // MARK: Sampling

  private static func decimal(_ value: Expr) -> BigDecimal? {
    if case .number(let n) = value { return BigDecimal(n, precision: 330) }
    return value.realValue
  }

  /// The expression at `target ± 10^e` for each `e` in `exponents` (or at `±10^|e|` for a point at infinity), each to 330
  /// digits; `nil` unless every one could be computed.
  private func sequence(
    _ exponents: [Int], from target: BigDecimal, direction: Int, scaleIsOutward: Bool = false
  )
    -> [BigDecimal]?
  {
    var values: [BigDecimal] = []
    for exponent in exponents {
      let offset = BigDecimal(BigInt(1), exponent: scaleIsOutward ? abs(exponent) : exponent)
      let point =
        scaleIsOutward ? (direction > 0 ? offset : -offset) : (direction > 0 ? target + offset : target - offset)
      guard let value = try? expression.approximation(precision: 330, values: [variable: point]) else { return nil }
      values.append(value)
    }
    return values
  }

  // MARK: Judging a sequence

  private func behaviour(of values: [BigDecimal]) -> Behaviour {
    guard values.count >= 3 else { return .unclear }

    // Values of astronomical size are compared by size alone: subtracting them would mean lining up millions of digits.
    if let order = values.last?.decimalOrder, order > 60 {
      let orders = values.map { $0.decimalOrder ?? Int.min }
      let rising = zip(orders, orders.dropFirst()).allSatisfy { $1 > $0 }
      let sameSign = values.allSatisfy { $0.isNegative == values[0].isNegative }
      return rising && sameSign ? .grows(negative: values[0].isNegative) : .unclear
    }
    // Values far smaller than anything that matters settle at zero as long as they keep shrinking.
    if let order = values.last?.decimalOrder, order < -60 {
      let orders = values.map { $0.decimalOrder ?? Int.min }
      let falling = zip(orders, orders.dropFirst()).allSatisfy { $1 < $0 }
      return falling ? .settles(BigDecimal(0), error: BigDecimal(BigInt(1), exponent: -60)) : .unclear
    }
    let tail = Array(values.suffix(3))
    let scale = max(BigDecimal(1), tail[2].magnitude)
    let step1 = (tail[1] - tail[0]).magnitude
    let step2 = (tail[2] - tail[1]).magnitude
    let tolerance = scale * BigDecimal(BigInt(1), exponent: -9)
    if step1 <= tolerance && step2 <= tolerance {
      return .settles(tail[2], error: max(step2, BigDecimal(BigInt(1), exponent: -40)))
    }

    // Growing without bound: the magnitude rises at every step and the sign does not change.
    let magnitudes = values.map(\.magnitude)
    let rising = zip(magnitudes, magnitudes.dropFirst()).allSatisfy { $1 > $0 }
    let sameSign = values.allSatisfy { $0.isNegative == values[0].isNegative } && values.allSatisfy { !$0.isZero }
    let large = magnitudes.last! > BigDecimal(30)
    // A logarithm keeps adding the same amount; anything that settles adds less each time.
    let notSlowing = step2 >= step1 * BigDecimal(BigInt(5), exponent: -1)
    if rising && sameSign && large && notSlowing { return .grows(negative: values[0].isNegative) }
    return .unclear
  }

  private func combine(_ sides: [Behaviour]) throws(MathError) -> Expr {
    var finite: [(BigDecimal, BigDecimal)] = []
    var directions: [Bool] = []
    for side in sides {
      switch side {
      case .settles(let value, let error): finite.append((value, error))
      case .grows(let negative): directions.append(negative)
      case .unclear: throw .undefined
      }
    }
    if !finite.isEmpty && !directions.isEmpty { throw .undefined }  // one side settles and the other grows
    if !directions.isEmpty {
      guard directions.allSatisfy({ $0 == directions[0] }) else { throw .undefined }  // +∞ on one side, −∞ on the other
      return directions[0] ? -Expr.infinity : Expr.infinity
    }
    // The sides must agree.
    let first = finite[0].0
    for (value, error) in finite.dropFirst() {
      let slack = max(error, finite[0].1) * BigDecimal(10) + BigDecimal(BigInt(1), exponent: -12)
      if (value - first).magnitude > slack * max(BigDecimal(1), first.magnitude) { throw .undefined }
    }
    guard let exact = Recognition.exactValue(of: first, error: finite[0].1) else { throw .unsupported }
    return exact
  }
}

/// Recognising a decimal as an exact number: zero, a fraction with a small denominator, or such a fraction of a common constant.
enum Recognition {
  static func exactValue(of value: BigDecimal, error: BigDecimal) -> Expr? {
    let tolerance = max(error * BigDecimal(100), BigDecimal(BigInt(1), exponent: -22))
    if value.magnitude <= tolerance { return .zero }
    if let rational = fraction(value, maxDenominator: 100_000, tolerance: tolerance) { return .number(rational) }

    let constants: [(Expr, BigDecimal?)] = [
      (.pi, try? Expr.pi.approximation(precision: 50)),
      (.pi * .pi, try? (Expr.pi * Expr.pi).approximation(precision: 50)),
      (.e, try? Expr.e.approximation(precision: 50)),
      (Expr.makePower(.e, .integer(2)), try? Expr.makePower(.e, .integer(2)).approximation(precision: 50)),
      (Expr.makePower(.e, .minusOne), try? Expr.makePower(.e, .minusOne).approximation(precision: 50)),
      ((try? Expr.apply(.ln, [.integer(2)])) ?? .zero, try? BigDecimal(2).ln(precision: 50)),
      ((try? Expr.apply(.ln, [.integer(3)])) ?? .zero, try? BigDecimal(3).ln(precision: 50)),
      (Expr.makePower(.integer(2), .fraction(1, 2)), try? BigDecimal(2).squareRoot(precision: 50)),
      (Expr.makePower(.integer(3), .fraction(1, 2)), try? BigDecimal(3).squareRoot(precision: 50)),
      (Expr.makePower(.integer(5), .fraction(1, 2)), try? BigDecimal(5).squareRoot(precision: 50)),
    ]
    for (constant, decimal) in constants {
      guard let decimal, !decimal.isZero, !constant.isZero, let ratio = try? value.divided(by: decimal, precision: 50)
      else {
        continue
      }
      // The constant divides the tolerance too, but it can be as small as 1/e, so be a little generous.
      if let rational = fraction(ratio, maxDenominator: 1_000, tolerance: tolerance * BigDecimal(10)) {
        return Expr.number(rational) * constant
      }
    }
    return nil
  }

  /// The fraction with the smallest denominator (up to `maxDenominator`) within `tolerance` of `value`, by continued fractions.
  static func fraction(_ value: BigDecimal, maxDenominator: Int, tolerance: BigDecimal) -> Rational? {
    let target = value.rational
    var remainder = target
    var (previousNumerator, numerator) = (BigInt(1), target.numerator.floorDivided(by: target.denominator))
    var (previousDenominator, denominator) = (BigInt(0), BigInt(1))
    remainder = remainder - Rational(numerator)
    for _ in 0..<40 {
      let candidate = Rational(numerator, denominator)
      if (BigDecimal(candidate, precision: 60) - value).magnitude <= tolerance { return candidate }
      if remainder.isZero { return candidate }
      let inverse = remainder.reciprocal
      let step = inverse.numerator.floorDivided(by: inverse.denominator)
      remainder = inverse - Rational(step)
      (previousNumerator, numerator) = (numerator, step * numerator + previousNumerator)
      (previousDenominator, denominator) = (denominator, step * denominator + previousDenominator)
      if denominator > BigInt(maxDenominator) { return nil }
    }
    return nil
  }
}
