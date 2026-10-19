// Sums: Σ f(k) for k from a to b.
//
// A short finite sum is added term by term. A longer one, or one with a symbolic end (`n`), has a closed form when the
// summand is a polynomial in k (Newton's forward differences give the sum as a polynomial in the number of terms) or a
// geometric term (with a polynomial factor, by differentiating the geometric series). An infinite sum is a geometric series,
// a rational function that telescopes (partial fractions with whole-number roots), a power k⁻²ⁿ (ζ of an even number), an
// alternating 1/k or 1/k², or an exponential series Σ rᵏ/k!. Anything else is not worked out.

enum Series {
  /// Σ f(k) for k from `a` to `b` (`nil` for ∞).
  static func sum(_ f: Expr, _ k: String, from a: Expr, to b: Expr?) throws(MathError) -> Expr {
    guard let start = a.rational, start.isInteger, let first = start.numerator.asInt, abs(first) < 1_000_000 else {
      throw .unsupported
    }
    guard let b else { return try infiniteSum(f, k, from: first) }

    if let end = b.rational, end.isInteger, let last = end.numerator.asInt {
      if last < first { return .zero }
      if last - first <= 400 { return try explicitSum(f, k, first, last) }
      // A long sum of numbers is a number, which is worth adding up; one of anything else would be a page of terms.
      if last - first <= 5000, let total = rationalSum(f, k, first, last) { return total }
    }
    if let result = polynomialSum(f, k, from: first, to: b) { return result }
    if let result = geometricSum(f, k, from: first, to: b) { return result }
    throw .unsupported
  }

  // MARK: Finite sums

  private static func explicitSum(_ f: Expr, _ k: String, _ first: Int, _ last: Int) throws(MathError) -> Expr {
    var terms: [Expr] = []
    for index in first...last {
      guard let term = f.substituting(k, with: .integer(index)) else { throw .divisionByZero }
      terms.append(term)
    }
    return Expr.makeSum(terms)
  }

  /// The sum when every term is a rational number; `nil` as soon as one is not.
  private static func rationalSum(_ f: Expr, _ k: String, _ first: Int, _ last: Int) -> Expr? {
    var total = Rational(0)
    for index in first...last {
      guard case .number(let term)? = f.substituting(k, with: .integer(index)) else { return nil }
      total += term
    }
    return .number(total)
  }

  /// A polynomial in `k`: the partial sums `S(n)` at `n = a − 1, a, …, a + d` are known, and Newton's forward differences give
  /// `S(n) = Σ Δᵐ S(a−1) · C(n − a + 1, m)`, a polynomial in the number of terms.
  private static func polynomialSum(_ f: Expr, _ k: String, from a: Int, to b: Expr) -> Expr? {
    guard let polynomial = f.polynomial(in: k), polynomial.degree >= 0, polynomial.degree <= 12 else { return nil }
    let d = polynomial.degree
    var values: [Expr] = [.zero]
    for index in 0...(d + 1) {
      guard let term = f.substituting(k, with: .integer(a + index)) else { return nil }
      values.append(values[index] + term)
    }
    var differences: [Expr] = []
    var row = values
    for _ in 0...(d + 1) {
      differences.append(row[0])
      row = zip(row, row.dropFirst()).map { $1 - $0 }
    }
    let terms = b - .integer(a) + .one  // the number of terms
    var total: [Expr] = []
    var binomial: Expr = .one  // C(terms, m)
    for (m, difference) in differences.enumerated() {
      if m > 0 {
        binomial = Expr.makeProduct([binomial, terms - .integer(m - 1), .number(Rational(1, m))])
      }
      total.append(Expr.makeProduct([difference, binomial]))
    }
    return Expr.makeSum(total).expanded()
  }

  // MARK: Geometric terms

  /// `f = coefficient · ratio^k`, or with a polynomial factor `P(k) · coefficient · ratio^k`.
  private static func geometricParts(
    _ f: Expr, _ k: String
  ) -> (coefficient: Expr, ratio: Expr, polynomial: Polynomial)? {
    let factors: [Expr]
    if case .product(let inner) = f { factors = inner } else { factors = [f] }
    var coefficient: [Expr] = []
    var polynomialFactors: [Expr] = []
    var ratio: Expr?
    var offset: Expr = .zero
    for factor in factors {
      if !factor.contains(k) {
        coefficient.append(factor)
      } else if case .power(let base, let exponent) = factor, !base.contains(k),
        let (slope, constant) = exponent.linear(in: k)
      {
        guard ratio == nil, let power = try? base.raised(to: .number(slope)) else { return nil }
        ratio = power
        offset = constant
        // base^(slope·k + constant) = (base^slope)^k · base^constant
        guard let shift = try? base.raised(to: constant) else { return nil }
        coefficient.append(shift)
      } else if factor.polynomial(in: k) != nil {
        polynomialFactors.append(factor)
      } else {
        return nil
      }
    }
    guard let ratio, let polynomial = Expr.makeProduct(polynomialFactors).polynomial(in: k) else { return nil }
    _ = offset
    return (Expr.makeProduct(coefficient), ratio, polynomial)
  }

  private static func geometricSum(_ f: Expr, _ k: String, from a: Int, to b: Expr) -> Expr? {
    guard let (coefficient, ratio, polynomial) = geometricParts(f, k), polynomial.degree == 0, !ratio.contains(k),
      let one = Optional(Expr.one), ratio != one
    else { return nil }
    // Σ_{k=a}^{b} ρᵏ = (ρ^(b+1) − ρ^a)/(ρ − 1)
    guard let top = try? ratio.raised(to: b + .one) - ratio.raised(to: .integer(a)),
      let quotient = try? top.divided(by: ratio - one)
    else { return nil }
    return Expr.makeProduct([coefficient, polynomial.coefficients[0], quotient])
  }

  // MARK: Infinite sums

  private static func infiniteSum(_ f: Expr, _ k: String, from a: Int) throws(MathError) -> Expr {
    if let result = try geometricSeries(f, k, from: a) { return result }
    if let result = try telescopingSeries(f, k, from: a) { return result }
    if let result = zetaSeries(f, k, from: a) { return result }
    if let result = exponentialSeries(f, k, from: a) { return result }
    // A polynomial (a constant, k, k²) does not tend to zero, so the sum has no value.
    if f.polynomial(in: k) != nil, !f.isZero { throw .undefined }
    throw .unsupported
  }

  /// `P(k) ρᵏ` with |ρ| < 1: `Σ ρᵏ = ρ^a/(1 − ρ)`, and each factor `k` is `ρ d/dρ`.
  private static func geometricSeries(_ f: Expr, _ k: String, from a: Int) throws(MathError) -> Expr? {
    guard let (coefficient, ratio, polynomial) = geometricParts(f, k), !ratio.contains(k) else { return nil }
    guard let magnitude = ratio.realValue ?? (try? ratio.approximation(precision: 30)) else { return nil }
    if magnitude.magnitude >= BigDecimal(1) { throw .undefined }  // diverges (or |ρ| = 1, which has no sum)

    let q = Expr.symbol("q#")
    guard let denominator = try? (Expr.one - q).raised(to: .minusOne),
      var series = try? q.raised(to: .integer(a)) * denominator
    else { return nil }
    var terms: [Expr] = []
    for (power, c) in polynomial.coefficients.enumerated() {
      terms.append(c * series)
      guard let slope = try? series.derivative("q#") else { return nil }
      series = (q * slope)
      _ = power
    }
    guard let sum = Expr.makeSum(terms).substituting("q#", with: ratio) else { return nil }
    return Expr.makeProduct([coefficient, sum])
  }

  /// A rational function with whole-number poles: `Σ Aᵢ/(k − rᵢ)` with `ΣAᵢ = 0` is `−Σ Aᵢ H(a − rᵢ − 1)`, harmonic numbers.
  private static func telescopingSeries(_ f: Expr, _ k: String, from a: Int) throws(MathError) -> Expr? {
    guard let (numerator, denominators) = f.together(variable: k), !denominators.isEmpty,
      let top = numerator.polynomial(in: k)?.rationalCoefficients
    else { return nil }
    var denominator = Expr.one
    for (base, power) in denominators { denominator = denominator * Expr.makePower(base, .integer(power)) }
    guard let bottom = denominator.expanded().polynomial(in: k)?.rationalCoefficients else { return nil }
    let numeratorPolynomial = RationalPolynomial(top)
    var rest = RationalPolynomial(bottom)
    guard numeratorPolynomial.degree < rest.degree else { return nil }

    // All roots whole numbers, each simple.
    let leading = rest.leading
    rest = RationalPolynomial(rest.coefficients.map { $0 / leading })
    var roots: [Int] = []
    var zeroRoots = 0
    while rest.degree >= 1, rest[0].isZero {
      rest = RationalPolynomial(Array(rest.coefficients.dropFirst()))
      zeroRoots += 1
    }
    if zeroRoots > 0 { roots += Array(repeating: 0, count: zeroRoots) }
    while rest.degree >= 1 {
      let (found, remaining) = rest.rationalRoots()
      if found.isEmpty { return nil }
      for root in found {
        guard root.isInteger, let whole = root.numerator.asInt else { return nil }
        roots.append(whole)
      }
      rest = remaining
    }
    guard rest.degree == 0, Set(roots).count == roots.count else { return nil }

    // Residues Aᵢ = N(rᵢ) / D′(rᵢ) for the monic denominator, then divided by the leading coefficient.
    let monic = RationalPolynomial(bottom.map { $0 / leading })
    var residues: [Rational] = []
    for root in roots {
      let slope = monic.derivative.evaluate(Rational(root))
      guard !slope.isZero else { return nil }
      residues.append(numeratorPolynomial.evaluate(Rational(root)) / slope / leading)
    }
    var total = Rational(0)
    for residue in residues { total += residue }
    guard total.isZero else { throw .undefined }  // the terms are like 1/k: the series diverges
    guard roots.allSatisfy({ $0 < a }) else { throw .divisionByZero }

    // −Σ Aᵢ H(a − rᵢ − 1)
    var sum = Rational(0)
    for (residue, root) in zip(residues, roots) {
      var harmonic = Rational(0)
      let count = a - root - 1
      if count > 0 { for j in 1...count { harmonic += Rational(1, j) } }
      sum -= residue * harmonic
    }
    return .number(sum)
  }

  /// `c·k^(−2n)` (ζ of an even number), and `c·(−1)^k·k^(−s)` for s = 1, 2, 4 (the alternating series), from any start.
  private static func zetaSeries(_ f: Expr, _ k: String, from a: Int) -> Expr? {
    let factors: [Expr]
    if case .product(let inner) = f { factors = inner } else { factors = [f] }
    var coefficient: [Expr] = []
    var power: Int?
    var alternating = false
    for factor in factors {
      if !factor.contains(k) {
        coefficient.append(factor)
      } else if case .power(let base, let exponent) = factor, base == .symbol(k), let n = exponent.rational,
        n.isInteger,
        n.isNegative, let whole = n.numerator.asInt
      {
        power = -whole
      } else if case .power(.number(let base), let exponent) = factor, base == Rational(-1), exponent == .symbol(k) {
        alternating = true
      } else {
        return nil
      }
    }
    guard let s = power, a >= 1 || (a == 0 && false) else { return nil }
    let pi = Expr.pi
    let value: Expr
    if !alternating {
      let zeta: [Int: Expr] = [
        2: Expr.fraction(1, 6) * pi * pi, 4: Expr.fraction(1, 90) * Expr.makePower(pi, .integer(4)),
        6: Expr.fraction(1, 945) * Expr.makePower(pi, .integer(6)),
        8: Expr.fraction(1, 9450) * Expr.makePower(pi, .integer(8)),
        10: Expr.fraction(1, 93555) * Expr.makePower(pi, .integer(10)),
        12: Expr.fraction(691, 638_512_875) * Expr.makePower(pi, .integer(12)),
      ]
      guard let known = zeta[s] else { return nil }
      value = known
    } else {
      // Σ_{k≥1} (−1)^k k^(−s) = −η(s)
      switch s {
      case 1:
        guard let ln = try? Expr.apply(.ln, [.integer(2)]) else { return nil }
        value = -ln
      case 2: value = Expr.fraction(-1, 12) * pi * pi
      case 4: value = Expr.fraction(-7, 720) * Expr.makePower(pi, .integer(4))
      default: return nil
      }
    }
    // From a > 1 the first terms are taken off.
    var head: [Expr] = []
    if a > 1 {
      for index in 1..<a {
        guard let term = f.substituting(k, with: .integer(index)) else { return nil }
        head.append(term)
      }
    }
    // The coefficient multiplies the series, and the head terms already include it.
    let series = Expr.makeProduct(coefficient + [value])
    return series - Expr.makeSum(head)
  }

  /// `c·r^k/k!` from k = 0 (or k = a): `c·e^r`, less the first terms.
  private static func exponentialSeries(_ f: Expr, _ k: String, from a: Int) -> Expr? {
    guard a >= 0 else { return nil }
    let factors: [Expr]
    if case .product(let inner) = f { factors = inner } else { factors = [f] }
    var coefficient: [Expr] = []
    var ratio: Expr = .one
    var hasFactorial = false
    for factor in factors {
      if !factor.contains(k) {
        coefficient.append(factor)
      } else if case .power(.function(.factorial, let arguments), let exponent) = factor, arguments == [.symbol(k)],
        exponent == .minusOne
      {
        hasFactorial = true
      } else if case .power(let base, let exponent) = factor, !base.contains(k), exponent == .symbol(k) {
        ratio = base
      } else if case .symbol(let name) = factor, name == k, false {
        return nil
      } else {
        return nil
      }
    }
    guard hasFactorial else { return nil }
    var head: [Expr] = []
    if a > 0 {
      for index in 0..<a {
        guard let term = f.substituting(k, with: .integer(index)) else { return nil }
        head.append(term)
      }
    }
    return Expr.makeProduct(coefficient + [Expr.makePower(.e, ratio)]) - Expr.makeSum(head)
  }
}
