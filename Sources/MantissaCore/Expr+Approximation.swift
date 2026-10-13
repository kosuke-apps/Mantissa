// Evaluating an expression to a decimal.

extension Expr {
  /// A value is not worked out when that would take more than this many extra digits of precision to keep the result right:
  /// the sine of a number with 10^5 digits, or e to such a power, is not something to compute (and the latter is far beyond
  /// what a number here can hold anyway).
  static let maxExtraDigits = 100_000

  /// The value to `precision` significant digits. Symbols take their values from `values`; one with no value is
  /// `MathError.notNumeric`. Non-real results (such as the square root of a negative number) are `.domain`.
  public func approximation(
    precision: Int = BigDecimal.defaultPrecision, values: [String: BigDecimal] = [:]
  )
    throws(MathError) -> BigDecimal
  {
    precondition(precision >= 1, "Precision must be at least 1")
    return try evaluate(working: precision + 15, values: values).rounded(toSignificantDigits: precision)
  }

  func evaluate(working p: Int, values: [String: BigDecimal]) throws(MathError) -> BigDecimal {
    switch self {
    case .number(let value):
      return BigDecimal(value, precision: p)

    case .constant(let constant):
      switch constant {
      case .pi: return BigDecimal.pi(precision: p)
      case .e: return BigDecimal.e(precision: p)
      case .i: throw .domain  // not a real number
      }

    case .symbol(let name):
      guard let value = values[name] else { throw .notNumeric }
      return value

    case .sum(let terms):
      var total = BigDecimal(0)
      var largest = Int.min
      for term in terms {
        let value = try term.evaluate(working: p, values: values)
        if let order = value.decimalOrder { largest = max(largest, order) }
        total = total.adding(value, precision: p)
      }
      // A total far below its largest term is cancellation noise, not a value: sin²1 + cos²1 − 1 is 0.
      if let order = total.decimalOrder, order < largest - p + 8 { return BigDecimal(0) }
      return total

    case .product(let factors):
      var result = BigDecimal(1)
      for factor in factors {
        result = (result * (try factor.evaluate(working: p, values: values))).rounded(toSignificantDigits: p)
      }
      return result

    case .power(let base, let exponent):
      return try Expr.evaluatePower(base, exponent, working: p, values: values)

    case .function(let function, let arguments):
      var evaluated: [BigDecimal] = []
      for argument in arguments { evaluated.append(try argument.evaluate(working: p, values: values)) }
      // The trigonometric and hyperbolic functions turn an absolute error in the argument into the same absolute
      // error in the result, so a large argument needs that many more digits than the result does: cos(2·10^37)
      // from an argument good to 55 significant digits is good to about 18 places, not 55.
      if function.magnifiesArgumentError, let order = evaluated[0].decimalOrder, order > 0 {
        guard order <= Expr.maxExtraDigits else { throw .overflow }
        evaluated[0] = try arguments[0].evaluate(working: p + order + 3, values: values)
      }
      return try Expr.evaluate(function, evaluated, working: p)
    }
  }

  static func evaluatePower(
    _ base: Expr, _ exponent: Expr, working p: Int, values: [String: BigDecimal]
  ) throws(MathError) -> BigDecimal {
    var b = try base.evaluate(working: p, values: values)
    if let n = exponent.rational {
      if n.isInteger {
        guard let whole = n.numerator.asInt else { throw .overflow }
        // b^n magnifies the relative error of b by n.
        let digits = String(whole.magnitude).count
        if digits > 1 { b = try base.evaluate(working: p + digits + 3, values: values) }
        return try b.power(whole, precision: p)
      }
      if b.isNegative {
        // A root of a negative number is real only when the root is odd: (−8)^(2/3) = 4.
        guard !n.denominator.isEven else { throw .domain }
        let magnitude = try b.magnitude.power(BigDecimal(n, precision: p), precision: p)
        return n.numerator.isEven ? magnitude : -magnitude
      }
      return try b.power(BigDecimal(n, precision: p), precision: p)
    }
    var y = try exponent.evaluate(working: p, values: values)
    // b^y = e^(y ln b): an error ε in b or y becomes about |y ln b| ε in the result, so a large exponent needs more
    // digits in both.
    if let order = y.decimalOrder, order > 0 {
      guard order <= Expr.maxExtraDigits else { throw .overflow }
      y = try exponent.evaluate(working: p + order + 3, values: values)
      b = try base.evaluate(working: p + order + 3, values: values)
    }
    if b.isNegative {
      guard let whole = y.asInt else { throw .domain }
      return try b.power(whole, precision: p)
    }
    return try b.power(y, precision: p)
  }

  static func evaluate(
    _ function: MathFunction, _ x: [BigDecimal], working p: Int
  ) throws(MathError)
    -> BigDecimal
  {
    switch function {
    case .sin: return try x[0].sin(precision: p)
    case .cos: return try x[0].cos(precision: p)
    case .tan: return try x[0].tan(precision: p)
    case .asin: return try x[0].arcsine(precision: p)
    case .acos: return try x[0].arccosine(precision: p)
    case .atan: return x[0].arctangent(precision: p)
    case .sinh: return try x[0].sinh(precision: p)
    case .cosh: return try x[0].cosh(precision: p)
    case .tanh: return try x[0].tanh(precision: p)
    case .asinh: return try x[0].asinh(precision: p)
    case .acosh: return try x[0].acosh(precision: p)
    case .atanh: return try x[0].atanh(precision: p)
    case .ln: return try x[0].ln(precision: p)
    case .log: return try x[0].log(base: x[1], precision: p)
    case .abs: return x[0].magnitude
    case .floor: return BigDecimal(x[0].floor)
    case .ceil: return -BigDecimal((-x[0]).floor)
    case .round: return x[0].rounded(toPlaces: 0)
    case .factorial:
      guard let n = x[0].asInt, n >= 0 else { throw .domain }
      guard let value = NumberTheory.factorial(n) else { throw .overflow }
      return BigDecimal(value)
    case .combinations, .permutations:
      guard let n = x[0].asInt, let r = x[1].asInt, n >= 0, r >= 0, r <= n else { throw .domain }
      let value = function == .combinations ? NumberTheory.combinations(n, r) : NumberTheory.permutations(n, r)
      guard let result = value else { throw .overflow }
      return BigDecimal(result)
    case .gcd, .lcm:
      guard x[0].isInteger, x[1].isInteger else { throw .domain }
      let a = x[0].floor
      let b = x[1].floor
      let divisor = BigInt.gcd(a, b)
      if function == .gcd { return BigDecimal(divisor) }
      return divisor.isZero ? BigDecimal(0) : BigDecimal((a * b).magnitude / divisor)
    }
  }
}
