// Applying a function to canonical arguments: exact values at special points, symmetries, domain checks.

extension Expr {
  /// `function(arguments)` in canonical form. Exact values are returned where they exist (`sin(π/6)` is `1/2`,
  /// `ln(e)` is `1`, `5!` is `120`); otherwise the call is kept as written. Arguments outside the function's domain
  /// are errors when they are numbers; for other arguments the domain is checked when the value is approximated.
  public static func apply(_ function: MathFunction, _ arguments: [Expr]) throws(MathError) -> Expr {
    precondition(arguments.count == function.arity, "\(function.rawValue) takes \(function.arity) argument(s)")
    let x = arguments[0]
    switch function {
    case .sin, .cos, .tan: return try trigonometric(function, x)
    case .asin, .acos, .atan: return try inverseTrigonometric(function, x)
    case .sinh, .cosh, .tanh, .asinh, .acosh, .atanh: return try hyperbolic(function, x)
    case .ln: return try naturalLogarithm(x)
    case .log: return try logarithm(x, base: arguments[1])
    case .abs: return absoluteValue(x)
    case .floor, .ceil, .round: return try rounding(function, x)
    case .factorial: return try factorial(x)
    case .combinations, .permutations: return try counting(function, x, arguments[1])
    case .gcd, .lcm: return try gcdOrLcm(function, x, arguments[1])
    }
  }

  // MARK: Symmetry

  /// If `value` is a negative number or a product with a negative coefficient, the positive expression `-value`.
  private static func negatedIfNegative(_ value: Expr) -> Expr? {
    switch value {
    case .number(let number): return number.isNegative ? .number(-number) : nil
    case .product(let factors):
      if case .number(let coefficient) = factors[0], coefficient.isNegative { return -value }
      return nil
    default: return nil
    }
  }

  // MARK: Trigonometric functions

  /// `r` when the expression is `r·π` (including 0), else `nil`.
  private static func piMultiple(_ value: Expr) -> Rational? {
    switch value {
    case .number(let number): return number.isZero ? Rational(0) : nil
    case .constant(.pi): return Rational(1)
    case .product(let factors):
      if factors.count == 2, case .number(let coefficient) = factors[0], factors[1] == .pi { return coefficient }
      return nil
    default: return nil
    }
  }

  /// `k` when the expression is `kπ/12` for a whole number `k` (taken modulo 24, that is modulo a full turn).
  private static func twelfthsOfPi(_ value: Expr) -> Int? {
    guard let multiple = piMultiple(value) else { return nil }
    let twelfths = multiple * Rational(12)
    guard twelfths.isInteger else { return nil }
    var remainder = (twelfths.numerator % BigInt(24)).asInt ?? 0
    if remainder < 0 { remainder += 24 }
    return remainder
  }

  private static func trigonometric(_ function: MathFunction, _ x: Expr) throws(MathError) -> Expr {
    if function != .cos, let positive = negatedIfNegative(x) {
      return -(try trigonometric(function, positive))  // sin and tan are odd
    }
    if function == .cos, let positive = negatedIfNegative(x) { return try trigonometric(function, positive) }
    guard let k = twelfthsOfPi(x) else { return .function(function, [x]) }
    switch function {
    case .sin: return ExactTrigonometry.sine(ofTwelfths: k)
    case .cos: return ExactTrigonometry.sine(ofTwelfths: k + 6)
    default:
      guard let tangent = ExactTrigonometry.tangent(ofTwelfths: k) else { throw .noValue }  // tan(π/2) is undefined
      return tangent
    }
  }

  private static func inverseTrigonometric(_ function: MathFunction, _ x: Expr) throws(MathError) -> Expr {
    if function != .acos, let positive = negatedIfNegative(x) {
      return -(try inverseTrigonometric(function, positive))  // asin and atan are odd
    }
    if let number = x.rational, function != .atan, number.magnitude > Rational(1) { throw .domain }
    switch function {
    case .asin:
      if let k = ExactTrigonometry.twelfths(whoseSineIs: x) { return ExactTrigonometry.angle(twelfths: k) }
    case .acos:
      // acos(x) = π/2 − asin(x), valid for negative x too, since the lookup covers both signs.
      if let k = ExactTrigonometry.twelfths(whoseSineIs: x) { return ExactTrigonometry.angle(twelfths: 6 - k) }
    default:
      if let k = ExactTrigonometry.twelfths(whoseTangentIs: x) { return ExactTrigonometry.angle(twelfths: k) }
    }
    return .function(function, [x])
  }

  // MARK: Hyperbolic functions

  private static func hyperbolic(_ function: MathFunction, _ x: Expr) throws(MathError) -> Expr {
    let odd: Set<MathFunction> = [.sinh, .tanh, .asinh, .atanh]
    if let positive = negatedIfNegative(x) {
      if odd.contains(function) { return -(try hyperbolic(function, positive)) }
      if function == .cosh { return try hyperbolic(function, positive) }
    }
    if let number = x.rational {
      switch function {
      case .acosh where number < Rational(1): throw .domain
      case .atanh where number.magnitude == Rational(1): throw .noValue
      case .atanh where number.magnitude > Rational(1): throw .domain
      case .acosh where number == Rational(1): return .zero
      default: break
      }
    }
    if x.isZero { return function == .cosh ? .one : .zero }
    return .function(function, [x])
  }

  // MARK: Logarithms

  private static func naturalLogarithm(_ x: Expr) throws(MathError) -> Expr {
    if let number = x.rational {
      if number.isZero { throw .noValue }
      if number.signum < 0 { throw .domain }
      if number == Rational(1) { return .zero }
      return .function(.ln, [x])
    }
    if x == .e { return .one }
    if case .power(let base, let exponent) = x {
      if base == .e { return exponent }  // ln(e^k) = k for real k
      // ln(b^k) = k ln b for a positive base b and a number k.
      if base.isKnownPositive, exponent.rational != nil { return exponent * (try naturalLogarithm(base)) }
    }
    return .function(.ln, [x])
  }

  private static func logarithm(_ x: Expr, base: Expr) throws(MathError) -> Expr {
    if let number = base.rational, number.signum <= 0 || number == Rational(1) { throw .domain }
    if let number = x.rational {
      if number.signum < 0 { throw .domain }
      if number.isZero { throw .noValue }
    }
    if base == .e { return try naturalLogarithm(x) }
    if let value = x.rational, let radix = base.rational {
      if let exact = NumberTheory.exactLogarithm(of: value, base: radix) { return .number(exact) }
    }
    if x == base && base.isKnownPositive { return .one }
    // log_b(a^p) = p·log_b(a) when log_b(a) is a plain number: log₂(2^(2/3)) is 2/3.
    if case .power(let inner, let exponent) = x, inner.isKnownPositive, exponent.rational != nil,
      let reduced = try? logarithm(inner, base: base), reduced.rational != nil
    {
      return exponent * reduced
    }
    return .function(.log, [x, base])
  }

  // MARK: Absolute value, rounding

  private static func absoluteValue(_ x: Expr) -> Expr {
    if let positive = negatedIfNegative(x) { return absoluteValue(positive) }
    if let number = x.rational { return .number(number.magnitude) }
    // |a + bi| = √(a² + b²) for real a and b.
    if x.containsImaginaryUnit, let (real, imaginary) = x.complexParts() {
      return makePower(makeSum([makePower(real, .integer(2)), makePower(imaginary, .integer(2))]), .fraction(1, 2))
    }
    if x.isKnownPositive { return x }
    // |c·y| = |c|·|y| for a number c.
    if case .product(let factors) = x, case .number(let coefficient) = factors[0] {
      let rest = factors.count == 2 ? factors[1] : Expr.product(Array(factors.dropFirst()))
      return makeProduct([.number(coefficient.magnitude), absoluteValue(rest)])
    }
    if case .function(.abs, _) = x { return x }
    return .function(.abs, [x])
  }

  private static func rounding(_ function: MathFunction, _ x: Expr) throws(MathError) -> Expr {
    if let number = x.rational {
      return .number(Rational(roundedValue(function, of: number)))
    }
    guard x.freeSymbols.isEmpty, let value = try? x.approximation(precision: 60) else {
      return .function(function, [x])
    }
    // Decide only when the value is safely away from the boundary the function cuts at.
    let tolerance = BigDecimal(BigInt(1), exponent: -40)
    let fraction = value - BigDecimal(value.floor)
    let boundary: BigDecimal = function == .round ? BigDecimal(BigInt(5), exponent: -1) : BigDecimal(0)
    if (fraction - boundary).magnitude < tolerance || (function != .round && (BigDecimal(1) - fraction) < tolerance) {
      return .function(function, [x])
    }
    return .number(Rational(roundedValue(function, of: value.rational)))
  }

  private static func roundedValue(_ function: MathFunction, of number: Rational) -> BigInt {
    let floor = number.numerator.floorDivided(by: number.denominator)
    switch function {
    case .floor: return floor
    case .ceil: return number.isInteger ? floor : floor + BigInt(1)
    default:
      // Round half away from zero.
      let doubled = (number.magnitude + Rational(1, 2))
      let magnitude = doubled.numerator.floorDivided(by: doubled.denominator)
      return number.isNegative ? -magnitude : magnitude
    }
  }

  // MARK: Integer functions

  private static func factorial(_ x: Expr) throws(MathError) -> Expr {
    guard let number = x.rational else { return .function(.factorial, [x]) }
    guard number.isInteger, !number.isNegative, let n = number.numerator.asInt else { throw .domain }
    guard let value = NumberTheory.factorial(n) else { throw .overflow }
    return .number(Rational(value))
  }

  private static func counting(_ function: MathFunction, _ n: Expr, _ r: Expr) throws(MathError) -> Expr {
    guard let nValue = n.rational, let rValue = r.rational else { return .function(function, [n, r]) }
    guard nValue.isInteger, rValue.isInteger, let nInt = nValue.numerator.asInt, let rInt = rValue.numerator.asInt,
      nInt >= 0, rInt >= 0, rInt <= nInt
    else { throw .domain }
    let result =
      function == .combinations ? NumberTheory.combinations(nInt, rInt) : NumberTheory.permutations(nInt, rInt)
    guard let value = result else { throw .overflow }
    return .number(Rational(value))
  }

  private static func gcdOrLcm(_ function: MathFunction, _ a: Expr, _ b: Expr) throws(MathError) -> Expr {
    guard let x = a.rational, let y = b.rational else { return .function(function, [a, b]) }
    guard x.isInteger, y.isInteger else { throw .domain }
    let divisor = BigInt.gcd(x.numerator, y.numerator)
    if function == .gcd { return .number(Rational(divisor)) }
    if divisor.isZero { return .zero }
    return .number(Rational((x.numerator * y.numerator).magnitude / divisor))
  }
}

/// Exact sines, cosines and tangents at multiples of π/12 (15°), and the matching inverse lookups.
enum ExactTrigonometry {
  private static let sqrt2 = Expr.makePower(.integer(2), .fraction(1, 2))
  private static let sqrt3 = Expr.makePower(.integer(3), .fraction(1, 2))
  private static let sqrt6 = Expr.makePower(.integer(6), .fraction(1, 2))

  /// sin(kπ/12) for k = 0...6.
  private static let sineTable: [Expr] = [
    .zero,
    Expr.fraction(1, 4) * (sqrt6 - sqrt2),
    Expr.fraction(1, 2),
    Expr.fraction(1, 2) * sqrt2,
    Expr.fraction(1, 2) * sqrt3,
    Expr.fraction(1, 4) * (sqrt6 + sqrt2),
    .one,
  ]

  /// tan(kπ/12) for k = 0...5 (k = 6 is undefined).
  private static let tangentTable: [Expr] = [
    .zero,
    Expr.integer(2) - sqrt3,
    Expr.fraction(1, 3) * sqrt3,
    .one,
    sqrt3,
    Expr.integer(2) + sqrt3,
  ]

  /// sin(kπ/12) for any whole k.
  static func sine(ofTwelfths k: Int) -> Expr {
    var index = ((k % 24) + 24) % 24
    if index > 12 { return -sine(ofTwelfths: index - 12) }
    if index > 6 { index = 12 - index }
    return sineTable[index]
  }

  /// tan(kπ/12) for any whole k, or `nil` where it is undefined (odd multiples of π/2).
  static func tangent(ofTwelfths k: Int) -> Expr? {
    let index = ((k % 12) + 12) % 12
    if index == 6 { return nil }
    return index < 6 ? tangentTable[index] : -tangentTable[12 - index]
  }

  /// cos(kπ/12) + i·sin(kπ/12), the point on the unit circle at that angle.
  static func unitVector(ofTwelfths k: Int) -> Expr? {
    sine(ofTwelfths: k + 6) + Expr.makeProduct([sine(ofTwelfths: k), .i])
  }

  /// The angle kπ/12 as an expression.
  static func angle(twelfths k: Int) -> Expr {
    k == 0 ? .zero : Expr.makeProduct([.number(Rational(k, 12)), .pi])
  }

  /// `k` in -6...6 with sin(kπ/12) equal to `value`.
  static func twelfths(whoseSineIs value: Expr) -> Int? {
    for k in 0...6 {
      if sineTable[k] == value { return k }
      if -sineTable[k] == value { return -k }
    }
    return nil
  }

  /// `k` in -5...5 with tan(kπ/12) equal to `value`.
  static func twelfths(whoseTangentIs value: Expr) -> Int? {
    for k in 0...5 {
      if tangentTable[k] == value { return k }
      if -tangentTable[k] == value { return -k }
    }
    return nil
  }
}
