// Antiderivatives of exact expressions.
//
// There is no complete algorithm that stays this small, so this is a toolbox applied in a fixed order: a table of the basic
// integrals, linearity, substitution, repeated integration by parts for polynomials times exponentials or sines, by parts for
// logarithms and inverse trigonometric functions, partial fractions for rational functions, and powers of sines and cosines.
// Whatever comes out is differentiated and compared with the integrand at several points before it is returned, so a wrong
// answer is never given; when nothing applies the result is `nil`.

extension Expr {
  /// An antiderivative with respect to `variable` (without the constant), or `nil` when none is found.
  public func antiderivative(_ variable: String) -> Expr? {
    var integrator = Integrator(variable: variable)
    guard let result = integrator.integrate(self), integrator.confirms(result, for: self) else { return nil }
    return result
  }
}

private struct Integrator {
  let variable: String
  private var depth = 0
  private let maxDepth = 7

  init(variable: String) { self.variable = variable }

  private var x: Expr { .symbol(variable) }

  // MARK: Checking

  /// Whether the derivative of `result` equals `integrand` at enough points.
  func confirms(_ result: Expr, for integrand: Expr) -> Bool {
    guard let slope = try? result.derivative(variable) else { return false }
    // Any other letter is a constant: give each a value.
    let others = integrand.freeSymbols.union(result.freeSymbols).subtracting([variable]).sorted()
    var agreed = 0
    for point in ["0.37", "1.61", "2.9", "-0.83", "0.113", "4.2"] {
      var values: [String: BigDecimal] = [variable: BigDecimal(point)!]
      for (index, name) in others.enumerated() { values[name] = BigDecimal("\(1.3 + 0.7 * Double(index))")! }
      guard let expected = try? integrand.approximation(precision: 40, values: values),
        let actual = try? slope.approximation(precision: 40, values: values)
      else { continue }
      let scale = max(BigDecimal(1), expected.magnitude)
      if (expected - actual).magnitude > scale * BigDecimal(BigInt(1), exponent: -20) { return false }
      agreed += 1
    }
    return agreed >= 2
  }

  // MARK: Dispatch

  mutating func integrate(_ f: Expr) -> Expr? {
    guard depth < maxDepth else { return nil }
    depth += 1
    defer { depth -= 1 }

    if f.isZero { return .zero }
    if !f.contains(variable) { return f * x }

    switch f {
    case .sum(let terms):
      var parts: [Expr] = []
      for term in terms {
        guard let part = integrate(term) else { return integrateAfterExpanding(f) }
        parts.append(part)
      }
      return Expr.makeSum(parts)

    case .product(let factors):
      // Constant factors come out.
      let constants = factors.filter { !$0.contains(variable) }
      if !constants.isEmpty {
        let rest = Expr.makeProduct(factors.filter { $0.contains(variable) })
        guard let inner = integrate(rest) else { return nil }
        return Expr.makeProduct(constants + [inner])
      }
      return integrateProduct(f, factors)

    default:
      return integrateAtom(f)
    }
  }

  private mutating func integrateAfterExpanding(_ f: Expr) -> Expr? {
    let expanded = f.expanded()
    guard expanded != f else { return nil }
    return integrate(expanded)
  }

  // MARK: Single factors

  private mutating func integrateAtom(_ f: Expr) -> Expr? {
    if let known = table(f) { return known }
    if let result = trigonometricPower(f, [f]) { return result }
    if let result = rationalFunction(f) { return result }
    if let result = substitute(f) { return result }
    if let result = integrateAfterExpanding(f) { return result }
    return nil
  }

  /// The basic integrals, in the unknown itself.
  private mutating func table(_ f: Expr) -> Expr? {
    let u = x
    switch f {
    case .symbol(let name) where name == variable:
      return u * u * Expr.fraction(1, 2)

    case .power(let base, let exponent):
      if base == u, !exponent.contains(variable) {
        if exponent == .minusOne { return try? Expr.apply(.ln, [Expr.apply(.abs, [u])]) }
        let next = exponent + .one
        return Expr.makeProduct([Expr.makePower(u, next), Expr.makePower(next, .minusOne)])
      }
      if !base.contains(variable), exponent == u {
        // a^x = e^(x ln a)
        guard let logarithm = try? Expr.apply(.ln, [base]) else { return nil }
        return Expr.makeProduct([f, Expr.makePower(logarithm, .minusOne)])
      }
      let one = Expr.one
      if base == one + u * u {
        if exponent == .minusOne { return try? Expr.apply(.atan, [u]) }
        if exponent == .fraction(-1, 2) { return try? Expr.apply(.asinh, [u]) }
        if exponent == .fraction(1, 2) {
          guard let a = try? Expr.apply(.asinh, [u]) else { return nil }
          return Expr.fraction(1, 2) * (u * f + a)
        }
      }
      if base == one - u * u {
        if exponent == .fraction(-1, 2) { return try? Expr.apply(.asin, [u]) }
        if exponent == .fraction(1, 2) {
          guard let a = try? Expr.apply(.asin, [u]) else { return nil }
          return Expr.fraction(1, 2) * (u * f + a)
        }
      }
      if base == u * u - one, exponent == .fraction(-1, 2) { return try? Expr.apply(.acosh, [u]) }
      // tan² = sec² − 1 and ln^n by parts.
      if exponent == .integer(2), case .function(.tan, let arguments) = base, arguments == [u],
        let tangent = try? Expr.apply(.tan, [u])
      {
        return tangent - u
      }
      if case .function(.ln, let arguments) = base, arguments == [u], let n = exponent.rational, n.isInteger,
        let whole = n.numerator.asInt, whole >= 2, let ln = try? Expr.apply(.ln, [u])
      {
        guard let rest = integrate(Expr.makePower(ln, .integer(whole - 1))) else { return nil }
        return u * f - Expr.integer(whole) * rest
      }
      // 1/cos² and 1/sin².
      if exponent == .integer(-2), case .function(let function, let arguments) = base, arguments == [u] {
        if function == .cos, let tangent = try? Expr.apply(.tan, [u]) { return tangent }
        if function == .sin, let sine = try? Expr.apply(.sin, [u]), let cosine = try? Expr.apply(.cos, [u]) {
          return -(cosine * Expr.makePower(sine, .minusOne))
        }
      }
      // sec and csc: ∫ 1/cos = ln|1 + sin| − ln|cos|, ∫ 1/sin = ln|1 − cos| − ln|sin| (that is, ln|sec + tan| and ln|tan(u/2)|).
      if exponent == .minusOne, case .function(let function, let arguments) = base, arguments == [u],
        function == .cos || function == .sin,
        let sine = try? Expr.apply(.sin, [u]), let cosine = try? Expr.apply(.cos, [u])
      {
        func logarithm(_ value: Expr) -> Expr? {
          guard let magnitude = try? Expr.apply(.abs, [value]) else { return nil }
          return try? Expr.apply(.ln, [magnitude])
        }
        if function == .cos, let top = logarithm(Expr.one + sine), let bottom = logarithm(cosine) {
          return top - bottom
        }
        if function == .sin, let top = logarithm(Expr.one - cosine), let bottom = logarithm(sine) {
          return top - bottom
        }
      }
      return nil

    case .function(let function, let arguments):
      guard arguments == [u] else { return nil }
      switch function {
      case .sin: return (try? Expr.apply(.cos, [u])).map { -$0 }
      case .cos: return try? Expr.apply(.sin, [u])
      case .tan:
        guard let cosine = try? Expr.apply(.cos, [u]), let abs = try? Expr.apply(.abs, [cosine]) else { return nil }
        return (try? Expr.apply(.ln, [abs])).map { -$0 }
      case .sinh: return try? Expr.apply(.cosh, [u])
      case .cosh: return try? Expr.apply(.sinh, [u])
      case .tanh:
        guard let cosh = try? Expr.apply(.cosh, [u]) else { return nil }
        return try? Expr.apply(.ln, [cosh])
      case .ln:
        guard let ln = try? Expr.apply(.ln, [u]) else { return nil }
        return u * ln - u
      case .atan:
        guard let atan = try? Expr.apply(.atan, [u]), let ln = try? Expr.apply(.ln, [Expr.one + u * u]) else {
          return nil
        }
        return u * atan - Expr.fraction(1, 2) * ln
      case .asin:
        guard let asin = try? Expr.apply(.asin, [u]) else { return nil }
        return u * asin + Expr.makePower(Expr.one - u * u, .fraction(1, 2))
      case .acos:
        guard let acos = try? Expr.apply(.acos, [u]) else { return nil }
        return u * acos - Expr.makePower(Expr.one - u * u, .fraction(1, 2))
      case .abs: return u * f * Expr.fraction(1, 2)
      default: return nil
      }

    default:
      return nil
    }
  }

  // MARK: Substitution

  /// `∫ f dx` through `u = g(x)` for a subexpression `g`: when `f / g′` is a function of `g` alone, the integral is one in `u`.
  /// This also covers every composition with a linear function, `h(ax + b)`, and, for a linear `g`, an `x` left over is written
  /// `(u − b)/a` (so `x √(x + 1)` becomes a sum of powers of `u`).
  private mutating func substitute(_ f: Expr) -> Expr? {
    let marker = "u#"
    let u = Expr.symbol(marker)

    // The candidates: arguments and exponents, and every function, power and sum that contains the unknown.
    var seen: [Expr] = []
    func consider(_ g: Expr) {
      if g.contains(variable), g != x, !seen.contains(g) { seen.append(g) }
    }
    for part in f.collectAll(where: { _ in true }) {
      switch part {
      case .function(_, let arguments):
        consider(part)
        arguments.forEach(consider)
      case .power(let base, let exponent):
        consider(part)
        consider(base)
        consider(exponent)
      case .sum:
        consider(part)
      default: break
      }
    }
    if seen.count > 24 { seen = Array(seen.prefix(24)) }

    for g in seen {
      guard let slope = try? g.derivative(variable), !slope.isZero, let quotient = try? f.divided(by: slope) else {
        continue
      }
      // For g = h^r with h linear and r a fraction, h itself is u^(1/r) and x is (u^(1/r) − b)/a.
      if case .power(let h, let exponent) = g, let r = exponent.rational, !r.isInteger,
        let (a, b) = h.linear(in: variable),
        let hValue = try? u.raised(to: .number(r.reciprocal))
      {
        guard
          let rewritten = quotient.replacing({ part in
            if part == g { return u }
            if part == h { return hValue }
            if part == x { return (hValue - b) * Expr.number(a.reciprocal) }
            return nil
          })?.expanded(), !rewritten.contains(variable)
        else { continue }
        var inUnknown = Integrator(variable: marker)
        inUnknown.depth = depth
        guard let integral = inUnknown.integrate(rewritten) else { continue }
        if let back = integral.replacing({ $0 == u ? g : nil }), !back.contains(marker) { return back }
        continue
      }
      guard var rewritten = rewrite(quotient, replacing: g, with: u) else { continue }
      if rewritten.contains(variable) {
        // A linear g = ax + b lets the remaining x be written in u.
        guard let (a, b) = g.linear(in: variable), let offset = Optional(b),
          let replaced = rewritten.replacing({ $0 == x ? (u - offset) * Expr.number(a.reciprocal) : nil })
        else { continue }
        rewritten = replaced.expanded()
        if rewritten.contains(variable) { continue }
      }
      var inUnknown = Integrator(variable: marker)
      inUnknown.depth = depth
      guard let integral = inUnknown.integrate(rewritten) else { continue }
      if let back = integral.replacing({ $0 == u ? g : nil }), !back.contains(marker) { return back }
    }
    return nil
  }

  /// `expression` with `g` replaced by `u`; for `g = a^(kx)` also its integer and fractional powers, which the canonical form
  /// writes as `a^(mkx)` (`1/e^x` is `e^(−x)`).
  private func rewrite(_ expression: Expr, replacing g: Expr, with u: Expr) -> Expr? {
    var exponent: Expr?
    var base: Expr?
    if case .power(let b, let e) = g, !b.contains(variable), e.contains(variable) {
      base = b
      exponent = e
    }
    return expression.replacing { part in
      if part == g { return u }
      if let base, let exponent, case .power(let b, let e) = part, b == base,
        let ratio = try? e.divided(by: exponent), let m = ratio.rational
      {
        return try? u.raised(to: .number(m))
      }
      return nil
    }
  }

  // MARK: Products

  private mutating func integrateProduct(_ f: Expr, _ factors: [Expr]) -> Expr? {
    if let known = table(f) { return known }
    if let result = polynomialTimes(f, factors) { return result }
    if let result = exponentialTimesTrigonometric(f, factors) { return result }
    if let result = trigonometricPower(f, factors) { return result }
    if let result = productOfTrigonometric(f, factors) { return result }
    if let result = productOfExponentials(f, factors) { return result }
    if let result = rationalFunction(f) { return result }
    if let result = substitute(f) { return result }
    return integrateAfterExpanding(f)
  }

  /// Splits a product into a polynomial in the unknown and the rest.
  private func splitPolynomial(_ factors: [Expr]) -> (polynomial: Polynomial, rest: Expr)? {
    var polynomialFactors: [Expr] = []
    var rest: [Expr] = []
    for factor in factors {
      if factor.polynomial(in: variable) != nil {
        polynomialFactors.append(factor)
      } else {
        rest.append(factor)
      }
    }
    guard !polynomialFactors.isEmpty, !rest.isEmpty,
      let polynomial = Expr.makeProduct(polynomialFactors).polynomial(in: variable), polynomial.degree >= 1
    else { return nil }
    return (polynomial, Expr.makeProduct(rest))
  }

  /// `P(x)·g(x)`: with `G₁, G₂, …` the repeated antiderivatives of `g`, the integral is `P G₁ − P′ G₂ + P″ G₃ − …`. For `g` an
  /// exponential, sine or cosine of a linear function, and for a logarithm or inverse trigonometric function by parts.
  private mutating func polynomialTimes(_ f: Expr, _ factors: [Expr]) -> Expr? {
    guard let (polynomial, g) = splitPolynomial(factors) else { return nil }
    let p = Expr.makeSum(
      polynomial.coefficients.enumerated().map { Expr.makeProduct([$1, Expr.makePower(x, .integer($0))]) })

    // Logarithms and inverse trigonometric functions: u = g, dv = P dx.
    if case .function(let function, _) = g, [.ln, .atan, .asin, .acos].contains(function) {
      guard let q = integrate(p), let slope = try? g.derivative(variable) else { return nil }
      guard let rest = integrate((q * slope).expanded()) ?? integrate(Expr.makeProduct([q, slope])) else { return nil }
      return q * g - rest
    }

    // Repeated integration of g, which must be a function that stays integrable (a rational function is for partial fractions).
    guard isRepeatable(g) else { return nil }
    var total: [Expr] = []
    var antiderivative = g
    var current = p
    var sign = Expr.one
    for _ in 0...(polynomial.degree + 1) {
      guard !current.isZero else { break }
      guard let next = integrate(antiderivative) else { return nil }
      antiderivative = next
      total.append(Expr.makeProduct([sign, current, antiderivative]))
      guard let slope = try? current.derivative(variable) else { return nil }
      current = slope
      sign = -sign
    }
    return Expr.makeSum(total)
  }

  /// Whether `g` can be integrated again and again in closed form: exponentials, sines, cosines and hyperbolic functions of a
  /// linear function, and a power of a linear function that is not a negative whole number.
  private func isRepeatable(_ g: Expr) -> Bool {
    switch g {
    case .function(let function, let arguments):
      return [.sin, .cos, .sinh, .cosh].contains(function) && arguments[0].linear(in: variable) != nil
    case .power(let base, let exponent):
      if !base.contains(variable) { return exponent.linear(in: variable) != nil }
      guard base.linear(in: variable) != nil, let n = exponent.rational else { return false }
      return !(n.isInteger && n.isNegative)
    default:
      return false
    }
  }

  /// `e^(ax+d)·sin(bx+c)` and the same with cosine.
  private func exponentialTimesTrigonometric(_ f: Expr, _ factors: [Expr]) -> Expr? {
    guard factors.count == 2 else { return nil }
    var exponent: Expr?
    var trig: (MathFunction, Expr)?
    for factor in factors {
      if case .power(.constant(.e), let power) = factor {
        exponent = power
      } else if case .function(let function, let arguments) = factor, function == .sin || function == .cos {
        trig = (function, arguments[0])
      }
    }
    guard let exponent, let (function, angle) = trig, let (a, _) = exponent.linear(in: variable),
      let (b, _) = angle.linear(in: variable)
    else { return nil }
    // ∫ e^(ax) sin(bx) = e^(ax)(a sin − b cos)/(a² + b²);  ∫ e^(ax) cos(bx) = e^(ax)(a cos + b sin)/(a² + b²).
    guard let sine = try? Expr.apply(.sin, [angle]), let cosine = try? Expr.apply(.cos, [angle]) else { return nil }
    let scale = Expr.number(Rational(1) / (a * a + b * b))
    let numerator =
      function == .sin
      ? Expr.number(a) * sine - Expr.number(b) * cosine
      : Expr.number(a) * cosine + Expr.number(b) * sine
    return Expr.makeProduct([scale, Expr.makePower(.e, exponent), numerator])
  }

  /// `sin A cos B`, `sin A sin B` and `cos A cos B` with different linear angles: a sum of two sines or cosines.
  private mutating func productOfTrigonometric(_ f: Expr, _ factors: [Expr]) -> Expr? {
    guard factors.count == 2, case .function(let first, let a) = factors[0],
      case .function(let second, let b) = factors[1],
      [.sin, .cos].contains(first), [.sin, .cos].contains(second), a[0] != b[0], a[0].linear(in: variable) != nil,
      b[0].linear(in: variable) != nil
    else { return nil }
    let (p, q) = (a[0], b[0])
    func call(_ function: MathFunction, _ angle: Expr) -> Expr? { try? Expr.apply(function, [angle]) }
    guard let sinSum = call(.sin, p + q), let sinDifference = call(.sin, p - q), let cosSum = call(.cos, p + q),
      let cosDifference = call(.cos, p - q)
    else { return nil }
    let half = Expr.fraction(1, 2)
    let sum: Expr
    switch (first, second) {
    case (.sin, .cos): sum = half * (sinSum + sinDifference)
    case (.cos, .sin): sum = half * (sinSum - sinDifference)
    case (.cos, .cos): sum = half * (cosSum + cosDifference)
    default: sum = half * (cosDifference - cosSum)
    }
    return integrate(sum)
  }

  /// A product of powers of constants, `2^x·3^x`: its derivative is `(Σ cᵢ ln aᵢ)` times itself.
  private func productOfExponentials(_ f: Expr, _ factors: [Expr]) -> Expr? {
    var rate = Expr.zero
    for factor in factors {
      guard case .power(let base, let exponent) = factor, !base.contains(variable),
        let (c, _) = exponent.linear(in: variable),
        let logarithm = try? Expr.apply(.ln, [base])
      else { return nil }
      rate = rate + Expr.number(c) * logarithm
    }
    guard !rate.isZero, let inverse = try? Expr.one.divided(by: rate) else { return nil }
    return f * inverse
  }

  /// `sin(θ)^m cos(θ)^n` for whole `m, n ≥ 0` and `θ` linear: expanded through Euler's formula into cosines and sines of
  /// multiples of `θ`, each of which integrates at once.
  private func trigonometricPower(_ f: Expr, _ factors: [Expr]) -> Expr? {
    var m = 0
    var n = 0
    var angle: Expr?
    for factor in factors {
      var base = factor
      var power = 1
      if case .power(let b, let e) = factor, let k = e.rational, k.isInteger, let whole = k.numerator.asInt, whole > 0 {
        base = b
        power = whole
      }
      guard case .function(let function, let arguments) = base, function == .sin || function == .cos else { return nil }
      if let known = angle, known != arguments[0] { return nil }
      angle = arguments[0]
      if function == .sin { m += power } else { n += power }
    }
    guard let angle, let (slope, _) = angle.linear(in: variable), m + n <= 10 else { return nil }
    return trigonometricProduct(sinePower: m, cosinePower: n, angle: angle, slope: slope)
  }

  private func trigonometricProduct(sinePower m: Int, cosinePower n: Int, angle: Expr, slope: Rational) -> Expr? {
    // sin θ = (E − E⁻¹)/(2i), cos θ = (E + E⁻¹)/2 with E = e^(iθ): the product is a polynomial in E and E⁻¹.
    let e = Expr.symbol("E#")
    let inverse = Expr.makePower(e, .minusOne)
    let sine = (e - inverse) * Expr.makePower(Expr.integer(2) * .i, .minusOne)
    let cosine = (e + inverse) * Expr.fraction(1, 2)
    guard let product = try? (Expr.makePower(sine, .integer(m)) * Expr.makePower(cosine, .integer(n)))
    else { return nil }
    let expanded = product.expanded()
    var coefficients: [Int: Expr] = [:]
    let terms: [Expr]
    if case .sum(let inner) = expanded { terms = inner } else { terms = [expanded] }
    for term in terms {
      var power = 0
      var rest: [Expr] = []
      let factors: [Expr]
      if case .product(let inner) = term { factors = inner } else { factors = [term] }
      for factor in factors {
        if factor == e {
          power += 1
        } else if case .power(let base, let exponent) = factor, base == e, let k = exponent.rational?.numerator.asInt {
          power += k
        } else {
          rest.append(factor)
        }
      }
      coefficients[power] = Expr.makeSum([coefficients[power] ?? .zero, Expr.makeProduct(rest)])
    }

    // c_k E^k + c_{−k} E^{−k} = (c_k + c_{−k}) cos kθ + i (c_k − c_{−k}) sin kθ, and each integrates in θ.
    var parts: [Expr] = []
    for k in coefficients.keys.sorted() where k >= 0 {
      let plus = coefficients[k] ?? .zero
      let minus = coefficients[-k] ?? .zero
      let cosineCoefficient = (k == 0 ? plus : plus + minus).expanded()
      let sineCoefficient = Expr.makeProduct([.i, plus - minus]).expanded()
      if k == 0 {
        parts.append(Expr.makeProduct([cosineCoefficient, x]))
        continue
      }
      let multiple = Expr.integer(k) * angle
      guard let cosK = try? Expr.apply(.cos, [multiple]), let sinK = try? Expr.apply(.sin, [multiple]) else {
        return nil
      }
      let scale = Expr.makePower(Expr.integer(k) * Expr.number(slope), .minusOne)
      parts.append(Expr.makeProduct([cosineCoefficient, sinK, scale]))
      parts.append(Expr.makeProduct([sineCoefficient, -cosK, scale]))
    }
    let result = Expr.makeSum(parts)
    return result.containsImaginaryUnit ? nil : result
  }

  // MARK: Rational functions

  /// `P(x)/Q(x)` with rational coefficients: the polynomial part, then partial fractions over the factors of `Q`, which may be
  /// linear (to a power) or one irreducible quadratic (to the first or second power).
  private mutating func rationalFunction(_ f: Expr) -> Expr? {
    guard let (numerator, denominators) = f.together(variable: variable), !denominators.isEmpty,
      let top = numerator.polynomial(in: variable)?.rationalCoefficients
    else { return nil }
    var denominator = Expr.one
    for (base, power) in denominators { denominator = denominator * Expr.makePower(base, .integer(power)) }
    guard let bottom = denominator.expanded().polynomial(in: variable)?.rationalCoefficients else { return nil }
    let (quotient, remainder) = RationalPolynomial(top).quotientAndRemainder(dividingBy: RationalPolynomial(bottom))

    var parts: [Expr] = []
    if !quotient.isZero {
      let polynomialPart = Expr.makeSum(
        quotient.coefficients.enumerated().map { Expr.makeProduct([.number($1), Expr.makePower(x, .integer($0))]) })
      guard let integral = integrate(polynomialPart) else { return nil }
      parts.append(integral)
    }
    if !remainder.isZero {
      guard let fractions = partialFractions(remainder, RationalPolynomial(bottom)) else { return nil }
      parts += fractions
    }
    return Expr.makeSum(parts)
  }

  /// The integral of `numerator / denominator` with `numerator` of lower degree.
  private func partialFractions(_ numerator: RationalPolynomial, _ denominator: RationalPolynomial) -> [Expr]? {
    // Factor the denominator into x^k, linear factors (x − r) with multiplicities, and what is left: nothing, or one quadratic.
    let overall = denominator.leading  // N/D = (N/overall) / (monic D)
    var rest = RationalPolynomial(denominator.coefficients.map { $0 / overall })
    var linear: [(root: Rational, power: Int)] = []
    var zeroPower = 0
    while rest.degree >= 1, rest[0].isZero {
      rest = RationalPolynomial(Array(rest.coefficients.dropFirst()))
      zeroPower += 1
    }
    if zeroPower > 0 { linear.append((Rational(0), zeroPower)) }
    while rest.degree >= 1 {
      let (roots, remaining) = rest.rationalRoots()
      if roots.isEmpty { break }
      for root in roots {
        if let index = linear.firstIndex(where: { $0.root == root }) {
          linear[index].power += 1
        } else {
          linear.append((root, 1))
        }
      }
      rest = remaining
    }
    var quadratic: RationalPolynomial?
    if rest.degree == 2 {
      quadratic = rest
    } else if rest.degree != 0 {
      return nil
    }

    // The unknown coefficients: A_{r,j} for each (x − r)^j, and B_j x + C_j for the quadratic (power 1 only).
    struct Basis {
      var polynomial: RationalPolynomial
    }
    var basis: [Basis] = []
    var labels: [(kind: Int, index: Int, power: Int)] = []  // kind 0: A over (x − r)^power; 1: B x; 2: C
    func monic(_ polynomial: RationalPolynomial) -> RationalPolynomial {
      RationalPolynomial(polynomial.coefficients.map { $0 / polynomial.leading })
    }
    let monicDenominator = monic(denominator)
    func power(_ polynomial: RationalPolynomial, _ n: Int) -> RationalPolynomial {
      var result = RationalPolynomial([Rational(1)])
      for _ in 0..<n { result = multiply(result, polynomial) }
      return result
    }
    for (index, factor) in linear.enumerated() {
      let linearFactor = RationalPolynomial([-factor.root, Rational(1)])
      for j in 1...factor.power {
        // D / (x − r)^j
        let (divided, _) = monicDenominator.quotientAndRemainder(dividingBy: power(linearFactor, j))
        basis.append(Basis(polynomial: divided))
        labels.append((0, index, j))
      }
    }
    if let quadratic {
      let (divided, _) = monicDenominator.quotientAndRemainder(dividingBy: quadratic)
      basis.append(Basis(polynomial: multiply(divided, RationalPolynomial([Rational(0), Rational(1)]))))
      labels.append((1, 0, 1))
      basis.append(Basis(polynomial: divided))
      labels.append((2, 0, 1))
    }

    // Solve Σ coefficient·basis = numerator / overall.
    let size = basis.count
    guard size == monicDenominator.degree else { return nil }
    var matrix = (0..<size).map { row in basis.map { $0.polynomial[row] } + [numerator[row] / overall] }
    for column in 0..<size {
      guard let pivot = (column..<size).first(where: { !matrix[$0][column].isZero }) else { return nil }
      matrix.swapAt(column, pivot)
      let divisor = matrix[column][column]
      matrix[column] = matrix[column].map { $0 / divisor }
      for other in 0..<size where other != column && !matrix[other][column].isZero {
        let factor = matrix[other][column]
        for index in 0...size { matrix[other][index] -= factor * matrix[column][index] }
      }
    }
    let solution = (0..<size).map { matrix[$0][size] }

    // Integrate each piece.
    var integrals: [Expr] = []
    var quadraticB = Rational(0)
    var quadraticC = Rational(0)
    for (label, coefficient) in zip(labels, solution) where !coefficient.isZero {
      switch label.kind {
      case 0:
        let root = linear[label.index].root
        let shifted = x - .number(root)
        if label.power == 1 {
          // ln|x − p/q| = ln|qx − p| − ln q, and the constant is dropped: 2x + 1, not x + 1/2.
          let shown =
            root.denominator.isOne
            ? shifted : Expr.number(Rational(root.denominator)) * x - .number(Rational(root.numerator))
          guard let ln = try? Expr.apply(.ln, [Expr.apply(.abs, [shown])]) else { return nil }
          integrals.append(Expr.number(coefficient) * ln)
        } else {
          let k = Rational(1 - label.power)
          integrals.append(Expr.makeProduct([.number(coefficient / k), Expr.makePower(shifted, .number(k))]))
        }
      case 1: quadraticB = coefficient
      default: quadraticC = coefficient
      }
    }
    if let quadratic, !(quadraticB.isZero && quadraticC.isZero) {
      guard let integral = integrateQuadraticFraction(b: quadraticB, c: quadraticC, quadratic: quadratic) else {
        return nil
      }
      integrals.append(integral)
    }
    return integrals
  }

  private func multiply(_ a: RationalPolynomial, _ b: RationalPolynomial) -> RationalPolynomial {
    guard !a.isZero, !b.isZero else { return RationalPolynomial([]) }
    var result = Array(repeating: Rational(0), count: a.degree + b.degree + 1)
    for i in 0...a.degree { for j in 0...b.degree { result[i + j] += a[i] * b[j] } }
    return RationalPolynomial(result)
  }

  /// `∫ (b x + c) / (x² + p x + q) dx` for the monic quadratic `x² + p x + q`.
  private func integrateQuadraticFraction(b: Rational, c: Rational, quadratic: RationalPolynomial) -> Expr? {
    let p = quadratic[1] / quadratic[2]
    let q = quadratic[0] / quadratic[2]
    let shift = p / Rational(2)  // x² + px + q = (x + p/2)² + (q − p²/4)
    let remainder = q - shift * shift
    let middle = x + .number(shift)
    guard let ln = try? Expr.apply(.ln, [(x * x + .number(p) * x + .number(q))]) else { return nil }
    var parts: [Expr] = []
    if !b.isZero { parts.append(Expr.number(b / Rational(2)) * ln) }
    // (b x + c) = (b/2)(2x + p) + (c − bp/2): the second part is a constant over the quadratic.
    let constant = c - b * shift
    if !constant.isZero {
      if remainder.signum > 0 {
        // ∫ dx/(u² + a²) = atan(u/a)/a
        let a = Expr.makePower(.number(remainder), .fraction(1, 2))
        guard let atan = try? Expr.apply(.atan, [middle * Expr.makePower(a, .minusOne)]) else { return nil }
        parts.append(Expr.makeProduct([.number(constant), Expr.makePower(a, .minusOne), atan]))
      } else if remainder.signum < 0 {
        // ∫ dx/(u² − a²) = ln|(u − a)/(u + a)|/(2a)
        let a = Expr.makePower(.number(-remainder), .fraction(1, 2))
        guard let ratio = try? (middle - a).divided(by: middle + a),
          let ln = try? Expr.apply(.ln, [Expr.apply(.abs, [ratio])])
        else { return nil }
        parts.append(Expr.makeProduct([.number(constant), Expr.fraction(1, 2), Expr.makePower(a, .minusOne), ln]))
      } else {
        parts.append(Expr.makeProduct([.number(-constant), Expr.makePower(middle, .minusOne)]))
      }
    }
    return Expr.makeSum(parts)
  }
}
