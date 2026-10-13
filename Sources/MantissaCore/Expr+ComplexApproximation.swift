// Evaluating an expression to a complex decimal.

extension Expr {
  /// The value to `precision` significant digits as a complex number. Real subexpressions are computed exactly as in
  /// `approximation`, so a real value comes back with a zero imaginary part and the same digits.
  ///
  /// Where the real and complex values of a power differ, the convention of the exact layer holds: an odd root of a
  /// negative number is the real root (∛(−8) is −2), and an even root is the principal one (√(−4) is 2i).
  public func complexApproximation(
    precision: Int = BigDecimal.defaultPrecision, values: [String: BigDecimal] = [:]
  )
    throws(MathError) -> ComplexDecimal
  {
    precondition(precision >= 1, "Precision must be at least 1")
    let p = precision + 15
    var result = try complexEvaluate(working: p, values: values)
    // One component far below the other is rounding noise, not a value: e^(iπ) is −1, not −1 + 1.2e-61 i.
    result.real = Expr.snapped(result.real, against: result.imaginary, working: p)
    result.imaginary = Expr.snapped(result.imaginary, against: result.real, working: p)
    return result.rounded(toSignificantDigits: precision)
  }

  private static func snapped(_ part: BigDecimal, against other: BigDecimal, working p: Int) -> BigDecimal {
    guard let order = part.decimalOrder, let largest = other.decimalOrder, order < largest - p + 8 else { return part }
    return BigDecimal(0)
  }

  private func complexEvaluate(working p: Int, values: [String: BigDecimal]) throws(MathError) -> ComplexDecimal {
    switch self {
    case .number(let value):
      return ComplexDecimal(real: BigDecimal(value, precision: p))

    case .constant(let constant):
      switch constant {
      case .pi: return ComplexDecimal(real: BigDecimal.pi(precision: p))
      case .e: return ComplexDecimal(real: BigDecimal.e(precision: p))
      case .i: return ComplexDecimal(real: BigDecimal(0), imaginary: BigDecimal(1))
      case .infinity: throw .overflow
      }

    case .symbol(let name):
      guard let value = values[name] else { throw .notNumeric }
      return ComplexDecimal(real: value)

    case .sum(let terms):
      var total = ComplexDecimal(real: BigDecimal(0))
      var largest = Int.min
      for term in terms {
        let value = try term.complexEvaluate(working: p, values: values)
        for part in [value.real, value.imaginary] {
          if let order = part.decimalOrder { largest = max(largest, order) }
        }
        total = total.adding(value, precision: p)
      }
      // A total far below its largest term is cancellation noise (see `evaluate`).
      for index in 0..<2 {
        let part = index == 0 ? total.real : total.imaginary
        guard let order = part.decimalOrder, order < largest - p + 8 else { continue }
        if index == 0 { total.real = BigDecimal(0) } else { total.imaginary = BigDecimal(0) }
      }
      return total

    case .product(let factors):
      var result = ComplexDecimal(real: BigDecimal(1))
      for factor in factors {
        result = result.multiplied(by: try factor.complexEvaluate(working: p, values: values), precision: p)
      }
      return result

    case .power(let base, let exponent):
      return try Expr.complexPower(base, exponent, working: p, values: values)

    case .function(let function, let arguments):
      return try Expr.complexFunction(function, arguments, working: p, values: values)
    }
  }

  // MARK: Powers

  private static func complexPower(
    _ base: Expr, _ exponent: Expr, working p: Int, values: [String: BigDecimal]
  ) throws(MathError) -> ComplexDecimal {
    var b = try base.complexEvaluate(working: p, values: values)
    var y = try exponent.complexEvaluate(working: p, values: values)

    // Real to a real power: the real code gives the full accuracy, and the real root of a negative number.
    if b.isReal && y.isReal {
      do throws(MathError) {
        return ComplexDecimal(real: try evaluatePower(base, exponent, working: p, values: values))
      } catch {
        guard error == .domain else { throw error }  // otherwise the principal value below
      }
    }

    if b.isZero {
      if y.real.signum > 0 && y.isReal { return ComplexDecimal(real: BigDecimal(0)) }
      throw y.isReal ? .divisionByZero : .domain
    }

    if y.isReal, let whole = y.real.asInt {
      // b^n magnifies the relative error of b by n.
      let digits = String(whole.magnitude).count
      if digits > 1 { b = try base.complexEvaluate(working: p + digits + 3, values: values) }
      return try b.power(whole, precision: p)
    }

    // b^y = e^(y ln b): an error ε in b or y becomes about |y ln b| ε in the result.
    let rough = try y.multiplied(by: b.ln(precision: 20), precision: 20)
    let extra = [rough.real, rough.imaginary, y.real, y.imaginary].compactMap(\.decimalOrder).max() ?? 0
    guard extra <= Expr.maxExtraDigits else { throw .overflow }
    if extra > 0 {
      b = try base.complexEvaluate(working: p + extra + 3, values: values)
      y = try exponent.complexEvaluate(working: p + extra + 3, values: values)
    }
    let product = try y.multiplied(by: b.ln(precision: p + extra + 3), precision: p + extra + 3)
    return try product.exp(precision: p)
  }

  // MARK: Functions

  private static func complexFunction(
    _ function: MathFunction, _ arguments: [Expr], working p: Int, values: [String: BigDecimal]
  ) throws(MathError) -> ComplexDecimal {
    var evaluated: [ComplexDecimal] = []
    for argument in arguments { evaluated.append(try argument.complexEvaluate(working: p, values: values)) }
    let z = evaluated[0]

    if evaluated.allSatisfy(\.isReal) {
      var reals = evaluated.map(\.real)
      if function.magnifiesArgumentError, let order = reals[0].decimalOrder, order > 0 {
        guard order <= Expr.maxExtraDigits else { throw .overflow }
        reals[0] = try arguments[0].evaluate(working: p + order + 3, values: values)
      }
      do throws(MathError) {
        return ComplexDecimal(real: try evaluate(function, reals, working: p))
      } catch {
        guard error == .domain else { throw error }
        // The logarithm of a negative number is complex; the other real functions have no complex value here.
        guard function == .ln || function == .log else { throw error }
      }
    }

    switch function {
    case .abs: return ComplexDecimal(real: try z.magnitude(precision: p))
    case .sin: return try z.sin(precision: p)
    case .cos: return try z.cos(precision: p)
    case .sinh: return try z.sinh(precision: p)
    case .cosh: return try z.cosh(precision: p)
    case .tan: return try z.sin(precision: p + 5).divided(by: z.cos(precision: p + 5), precision: p)
    case .tanh: return try z.sinh(precision: p + 5).divided(by: z.cosh(precision: p + 5), precision: p)
    case .ln: return try z.ln(precision: p)
    case .log:
      let numerator = try z.ln(precision: p + 5)
      return try numerator.divided(by: evaluated[1].ln(precision: p + 5), precision: p)
    default: throw .domain
    }
  }
}
