/// `diff`, `int`, `lim` and `sum`: the functions that work on an expression, with the unknown as an argument. They are
/// worked out while the input is turned into an `Expr`, so what comes out is the value (`diff(x², x)` is `2x`).
struct Calculus {
  let builder: Builder

  func evaluate(_ function: FunctionName, _ arguments: [Syntax]) throws(MathError) -> Expr {
    switch function {
    case .diff: return try differentiate(arguments)
    case .int: return try integrate(arguments)
    case .lim: return try limit(arguments)
    case .sum: return try series(arguments)
    default: throw .unsupported
    }
  }

  /// `diff(f)`, `diff(f, x)` or `diff(f, x, n)`.
  private func differentiate(_ arguments: [Syntax]) throws(MathError) -> Expr {
    let expression = try builder.build(arguments[0])
    let variable = try unknown(arguments, at: 1, in: expression)
    var order = 1
    if arguments.count > 2 {
      guard case .number(let n) = arguments[2], n.isInteger, let whole = n.numerator.asInt, whole >= 0, whole <= 20
      else {
        throw .domain
      }
      order = whole
    }
    return try expression.derivative(variable, order: order).combinedOverCommonDenominator(variable: variable)
  }

  /// `int(f)` or `int(f, x)`: an antiderivative, without the constant. `int(f, x, a, b)` is the definite integral, and either end
  /// may be ±∞.
  private func integrate(_ arguments: [Syntax]) throws(MathError) -> Expr {
    let expression = try builder.build(arguments[0])
    let variable = try unknown(arguments, at: 1, in: expression)
    let antiderivative = expression.antiderivative(variable)
    if antiderivative == nil || (arguments.count == 4 && Self.isGaussianLimits(arguments)) {
      // e^(−x²) has no elementary antiderivative, but its integral over the whole line is √π.
      if arguments.count == 4, let lower = try? point(arguments[2]), let upper = try? point(arguments[3]),
        let value = expression.gaussianIntegral(variable, from: lower, to: upper)
      {
        return value
      }
      guard antiderivative != nil else { throw .unsupported }
    }
    guard let antiderivative else { throw .unsupported }
    guard arguments.count > 2 else { return antiderivative }
    guard arguments.count == 4 else { throw .domain }

    let lower = try point(arguments[2])
    let upper = try point(arguments[3])
    try Self.requireNoInteriorSingularity(expression, variable, lower, upper)
    let top = try Self.value(of: antiderivative, variable, at: upper, side: .left)
    let bottom = try Self.value(of: antiderivative, variable, at: lower, side: .right)
    guard !top.containsInfinity, !bottom.containsInfinity else { throw .undefined }  // the integral diverges
    return top - bottom
  }

  /// Whether an end of the integral is infinite, where a Gaussian integral may apply even when there is an antiderivative.
  private static func isGaussianLimits(_ arguments: [Syntax]) -> Bool {
    func infinite(_ syntax: Syntax) -> Bool {
      if case .infinity = syntax { return true }
      if case .negate(.infinity) = syntax { return true }
      return false
    }
    return infinite(arguments[2]) || infinite(arguments[3])
  }

  /// A bound: a number (or expression) or ±∞.
  private func point(_ syntax: Syntax) throws(MathError) -> LimitPoint {
    switch syntax {
    case .infinity: return .plusInfinity
    case .negate(.infinity): return .minusInfinity
    default: return .finite(try builder.build(syntax))
    }
  }

  /// The antiderivative at a bound: its value, or its limit from inside the interval when it is not defined there.
  private static func value(
    of f: Expr, _ variable: String, at point: LimitPoint, side: LimitSide
  ) throws(MathError) -> Expr {
    if case .finite(let a) = point, let direct = f.substituting(variable, with: a),
      !direct.containsImaginaryUnit || f.containsImaginaryUnit
    {
      return direct
    }
    return try f.limit(variable, to: point, side: side)
  }

  /// A pole strictly inside the interval makes the integral diverge, however the antiderivative looks (ln|x| across 0).
  private static func requireNoInteriorSingularity(
    _ f: Expr, _ variable: String, _ lower: LimitPoint, _ upper: LimitPoint
  ) throws(MathError) {
    guard case .finite(let a) = lower, case .finite(let b) = upper, let low = a.realValue, let high = b.realValue,
      let (_, denominators) = f.together(variable: variable)
    else { return }
    for denominator in denominators {
      guard let polynomial = denominator.base.polynomial(in: variable), polynomial.degree >= 1,
        let roots = EquationSolver.roots(of: polynomial)
      else { continue }
      for root in roots {
        guard let c = root.realValue, c > low, c < high else { continue }
        // The expression is large on both sides of a true pole; a cancelled one is not.
        let near = BigDecimal(BigInt(1), exponent: -9)
        let big = BigDecimal(BigInt(1), exponent: 5)
        for point in [c - near, c + near] {
          if let v = try? f.approximation(precision: 40, values: [variable: point]), v.magnitude > big {
            throw .undefined
          }
        }
      }
    }
  }

  /// `sum(f, k, a, b)`, with `b` possibly ∞.
  private func series(_ arguments: [Syntax]) throws(MathError) -> Expr {
    let expression = try builder.build(arguments[0])
    guard case .symbol(let variable) = arguments[1] else { throw .domain }
    let start = try builder.build(arguments[2])
    var end: Expr?
    if case .infinity = arguments[3] { end = nil } else { end = try builder.build(arguments[3]) }
    return try Series.sum(expression, variable, from: start, to: end)
  }

  /// `lim(f, x, a)` or `lim(f, x, a, direction)`, with `a` a number or ±∞ and the direction 1 (from above) or −1 (from below).
  private func limit(_ arguments: [Syntax]) throws(MathError) -> Expr {
    let expression = try builder.build(arguments[0])
    guard case .symbol(let variable) = arguments[1] else { throw .domain }
    let point: LimitPoint
    switch arguments[2] {
    case .infinity: point = .plusInfinity
    case .negate(.infinity): point = .minusInfinity
    default: point = .finite(try builder.build(arguments[2]))
    }
    var side = LimitSide.both
    if arguments.count > 3 {
      switch arguments[3] {
      case .number(let n) where n == Rational(1): side = .right
      case .negate(.number(let n)) where n == Rational(1): side = .left
      default: throw .domain
      }
    }
    return try expression.limit(variable, to: point, side: side)
  }

  /// The unknown named by the argument at `index`, or the one letter the expression has (`x` first).
  func unknown(_ arguments: [Syntax], at index: Int, in expression: Expr) throws(MathError) -> String {
    if arguments.count > index {
      guard case .symbol(let name) = arguments[index] else { throw .domain }
      return name
    }
    return EquationSolver.unknown(in: expression.freeSymbols) ?? "x"
  }
}
