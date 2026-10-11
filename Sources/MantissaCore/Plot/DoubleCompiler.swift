import Foundation

/// A function of one real variable, in `Double`. `NaN` means undefined at that point (the square root of a negative
/// number, `ln(0)`); an infinity means a pole.
public typealias RealFunction = @Sendable (Double) -> Double

/// Turns an exact expression into a closure over `Double`, which is fast enough to draw a graph from. This is the one
/// place in the engine where `Double` is used for a result; nothing that is shown as exact comes from here.
enum DoubleCompiler {
  static func compile(_ expression: Expr, variable: String = "x") -> RealFunction {
    switch expression {
    case .number(let value):
      let number = double(value)
      return { _ in number }

    case .constant(let constant):
      let number = constant == .pi ? Double.pi : M_E
      return { _ in number }

    case .symbol(let name):
      if name == variable { return { x in x } }
      return { _ in Double.nan }

    case .sum(let terms):
      let parts = terms.map { compile($0, variable: variable) }
      return { x in
        var total = 0.0
        for part in parts { total += part(x) }
        return total
      }

    case .product(let factors):
      let parts = factors.map { compile($0, variable: variable) }
      return { x in
        var result = 1.0
        for part in parts { result *= part(x) }
        return result
      }

    case .power(let base, let exponent):
      return power(compile(base, variable: variable), exponent: exponent, variable: variable)

    case .function(let function, let arguments):
      let compiled = arguments.map { compile($0, variable: variable) }
      return apply(function, compiled)
    }
  }

  /// 0⁻¹ is undefined, not an infinity that later turns 1/(1/0) into 0.
  private static func finiteOrUndefined(_ value: Double) -> Double { value.isInfinite ? .nan : value }

  private static func double(_ value: Rational) -> Double {
    BigDecimal(value, precision: 20).doubleValue
  }

  private static func power(_ base: @escaping RealFunction, exponent: Expr, variable: String) -> RealFunction {
    if case .number(let value) = exponent {
      if value.isInteger, let whole = value.numerator.asInt {
        let n = Double(whole)
        return { x in finiteOrUndefined(pow(base(x), n)) }
      }
      // A rational power: an odd root of a negative number is real, an even root is not.
      let p = double(value)
      let oddDenominator = !value.denominator.isEven
      let oddNumerator = !value.numerator.isEven
      return { x in
        let b = base(x)
        if b >= 0 { return finiteOrUndefined(pow(b, p)) }
        guard oddDenominator else { return .nan }
        let magnitude = pow(-b, p)
        return finiteOrUndefined(oddNumerator ? -magnitude : magnitude)
      }
    }
    let power = compile(exponent, variable: variable)
    return { x in
      let b = base(x)
      let p = power(x)
      if b >= 0 || p == p.rounded() { return finiteOrUndefined(pow(b, p)) }
      return .nan
    }
  }

  private static func apply(_ function: MathFunction, _ arguments: [RealFunction]) -> RealFunction {
    let f = arguments[0]
    switch function {
    case .sin: return { sin(f($0)) }
    case .cos: return { cos(f($0)) }
    case .tan: return { tan(f($0)) }
    case .asin: return { asin(f($0)) }
    case .acos: return { acos(f($0)) }
    case .atan: return { atan(f($0)) }
    case .sinh: return { sinh(f($0)) }
    case .cosh: return { cosh(f($0)) }
    case .tanh: return { tanh(f($0)) }
    case .asinh: return { asinh(f($0)) }
    case .acosh: return { acosh(f($0)) }
    case .atanh: return { atanh(f($0)) }
    case .ln: return { x in f(x) > 0 ? log(f(x)) : .nan }
    case .log:
      let base = arguments[1]
      return { x in
        let value = f(x)
        let radix = base(x)
        return value > 0 && radix > 0 ? log(value) / log(radix) : .nan
      }
    case .abs: return { abs(f($0)) }
    case .floor: return { floor(f($0)) }
    case .ceil: return { ceil(f($0)) }
    case .round: return { f($0).rounded(.toNearestOrAwayFromZero) }
    case .factorial:
      return { x in
        let n = f(x)
        guard n >= 0, n == n.rounded(), n <= 170 else { return .nan }
        return tgamma(n + 1)
      }
    case .combinations, .permutations:
      let r = arguments[1]
      return { x in
        let n = f(x)
        let k = r(x)
        guard n >= 0, k >= 0, k <= n, n == n.rounded(), k == k.rounded(), n <= 170 else { return .nan }
        let permutations = tgamma(n + 1) / tgamma(n - k + 1)
        return function == .permutations ? permutations : permutations / tgamma(k + 1)
      }
    case .gcd, .lcm:
      let other = arguments[1]
      return { x in
        let a = f(x)
        let b = other(x)
        guard a == a.rounded(), b == b.rounded(), abs(a) < 1e15, abs(b) < 1e15 else { return .nan }
        var (p, q) = (Int(abs(a)), Int(abs(b)))
        let product = p * q
        while q != 0 { (p, q) = (q, p % q) }
        return function == .gcd ? Double(p) : (p == 0 ? 0 : Double(product / p))
      }
    }
  }
}
