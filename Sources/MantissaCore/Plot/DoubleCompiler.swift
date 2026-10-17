import Foundation

/// A function of one real variable, in `Double`. `NaN` means undefined at that point (the square root of a negative
/// number, `ln(0)`); an infinity means a pole.
public typealias RealFunction = @Sendable (Double) -> Double

/// A function of two real variables, `(x, y)`, for the curves and regions that are not the graph of a function.
public typealias PlaneFunction = @Sendable (Double, Double) -> Double

/// Turns an exact expression into a closure over `Double`, which is fast enough to draw a graph from. This is the one
/// place in the engine where `Double` is used for a result; nothing that is shown as exact comes from here.
enum DoubleCompiler {
  static func compile(_ expression: Expr, variable: String = "x") -> RealFunction {
    let plane = compilePlane(expression, x: variable, y: nil)
    return { x in plane(x, .nan) }
  }

  /// `expression` as a function of two variables; a symbol that is neither is undefined (`NaN`).
  static func compilePlane(_ expression: Expr, x: String = "x", y: String? = "y") -> PlaneFunction {
    compile(expression, variables: (x, y))
  }

  private static func compile(_ expression: Expr, variables: (x: String, y: String?)) -> PlaneFunction {
    switch expression {
    case .number(let value):
      let number = double(value)
      return { _, _ in number }

    case .constant(let constant):
      // A graph is of a real function; the imaginary unit has no real value.
      let number =
        constant == .pi ? Double.pi : (constant == .e ? M_E : (constant == .infinity ? Double.infinity : Double.nan))
      return { _, _ in number }

    case .symbol(let name):
      if name == variables.x { return { x, _ in x } }
      if name == variables.y { return { _, y in y } }
      return { _, _ in Double.nan }

    case .sum(let terms):
      let parts = terms.map { compile($0, variables: variables) }
      return { x, y in
        var total = 0.0
        for part in parts { total += part(x, y) }
        return total
      }

    case .product(let factors):
      let parts = factors.map { compile($0, variables: variables) }
      return { x, y in
        var result = 1.0
        for part in parts { result *= part(x, y) }
        return result
      }

    case .power(let base, let exponent):
      return power(compile(base, variables: variables), exponent: exponent, variables: variables)

    case .function(let function, let arguments):
      let compiled = arguments.map { compile($0, variables: variables) }
      return apply(function, compiled)
    }
  }

  /// 0⁻¹ is undefined, not an infinity that later turns 1/(1/0) into 0.
  private static func finiteOrUndefined(_ value: Double) -> Double { value.isInfinite ? .nan : value }

  private static func double(_ value: Rational) -> Double {
    BigDecimal(value, precision: 20).doubleValue
  }

  private static func power(
    _ base: @escaping PlaneFunction, exponent: Expr, variables: (x: String, y: String?)
  ) -> PlaneFunction {
    if case .number(let value) = exponent {
      if value.isInteger, let whole = value.numerator.asInt {
        let n = Double(whole)
        return { x, y in finiteOrUndefined(pow(base(x, y), n)) }
      }
      // A rational power: an odd root of a negative number is real, an even root is not.
      let p = double(value)
      let oddDenominator = !value.denominator.isEven
      let oddNumerator = !value.numerator.isEven
      return { x, y in
        let b = base(x, y)
        if b >= 0 { return finiteOrUndefined(pow(b, p)) }
        guard oddDenominator else { return .nan }
        let magnitude = pow(-b, p)
        return finiteOrUndefined(oddNumerator ? -magnitude : magnitude)
      }
    }
    let power = compile(exponent, variables: variables)
    return { x, y in
      let b = base(x, y)
      let p = power(x, y)
      if b >= 0 || p == p.rounded() { return finiteOrUndefined(pow(b, p)) }
      return .nan
    }
  }

  private static func apply(_ function: MathFunction, _ arguments: [PlaneFunction]) -> PlaneFunction {
    let f = arguments[0]
    switch function {
    case .sin: return { x, y in sin(f(x, y)) }
    case .cos: return { x, y in cos(f(x, y)) }
    case .tan: return { x, y in tan(f(x, y)) }
    case .asin: return { x, y in asin(f(x, y)) }
    case .acos: return { x, y in acos(f(x, y)) }
    case .atan: return { x, y in atan(f(x, y)) }
    case .sinh: return { x, y in sinh(f(x, y)) }
    case .cosh: return { x, y in cosh(f(x, y)) }
    case .tanh: return { x, y in tanh(f(x, y)) }
    case .asinh: return { x, y in asinh(f(x, y)) }
    case .acosh: return { x, y in acosh(f(x, y)) }
    case .atanh: return { x, y in atanh(f(x, y)) }
    case .ln: return { x, y in f(x, y) > 0 ? log(f(x, y)) : .nan }
    case .log:
      let base = arguments[1]
      return { x, y in
        let value = f(x, y)
        let radix = base(x, y)
        return value > 0 && radix > 0 ? log(value) / log(radix) : .nan
      }
    case .abs: return { x, y in abs(f(x, y)) }
    case .floor: return { x, y in floor(f(x, y)) }
    case .ceil: return { x, y in ceil(f(x, y)) }
    case .round: return { x, y in f(x, y).rounded(.toNearestOrAwayFromZero) }
    case .factorial:
      return { x, y in
        let n = f(x, y)
        guard n >= 0, n == n.rounded(), n <= 170 else { return .nan }
        return tgamma(n + 1)
      }
    case .combinations, .permutations:
      let r = arguments[1]
      return { x, y in
        let n = f(x, y)
        let k = r(x, y)
        guard n >= 0, k >= 0, k <= n, n == n.rounded(), k == k.rounded(), n <= 170 else { return .nan }
        let permutations = tgamma(n + 1) / tgamma(n - k + 1)
        return function == .permutations ? permutations : permutations / tgamma(k + 1)
      }
    case .gcd, .lcm:
      let other = arguments[1]
      return { x, y in
        let a = f(x, y)
        let b = other(x, y)
        guard a == a.rounded(), b == b.rounded(), abs(a) < 1e15, abs(b) < 1e15 else { return .nan }
        var (p, q) = (Int(abs(a)), Int(abs(b)))
        let product = p * q
        while q != 0 { (p, q) = (q, p % q) }
        return function == .gcd ? Double(p) : (p == 0 ? 0 : Double(product / p))
      }
    }
  }
}
