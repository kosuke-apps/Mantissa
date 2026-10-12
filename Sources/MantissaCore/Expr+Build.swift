// Smart constructors: every way of combining expressions goes through these, which is what keeps `Expr` canonical.

extension Expr {
  // MARK: Operators

  public static prefix func - (value: Expr) -> Expr { makeProduct([.minusOne, value]) }
  public static func + (lhs: Expr, rhs: Expr) -> Expr { makeSum([lhs, rhs]) }
  public static func - (lhs: Expr, rhs: Expr) -> Expr { makeSum([lhs, -rhs]) }
  public static func * (lhs: Expr, rhs: Expr) -> Expr { makeProduct([lhs, rhs]) }

  /// `self / divisor`. A zero divisor is an error.
  public func divided(by divisor: Expr) throws(MathError) -> Expr {
    if divisor.isZero { throw .divisionByZero }
    return Expr.makeProduct([self, Expr.makePower(divisor, .minusOne)])
  }

  /// `self ^ exponent`. `0^0` is a domain error and a negative power of zero is a division by zero.
  public func raised(to exponent: Expr) throws(MathError) -> Expr {
    if isZero, let power = exponent.rational {
      if power.isZero { throw .domain }
      if power.isNegative { throw .divisionByZero }
    }
    return Expr.makePower(self, exponent)
  }

  // MARK: Sums

  /// The sum of canonical expressions, in canonical form.
  static func makeSum(_ terms: [Expr]) -> Expr {
    var constant = Rational(0)
    var order: [Expr] = []
    var coefficients: [Expr: Rational] = [:]

    func add(_ term: Expr) {
      switch term {
      case .number(let value):
        constant += value
      case .sum(let inner):
        inner.forEach(add)
      default:
        let (coefficient, rest) = term.splitCoefficient()
        if coefficients[rest] == nil { order.append(rest) }
        coefficients[rest, default: Rational(0)] += coefficient
      }
    }
    terms.forEach(add)

    var result: [Expr] = []
    for rest in order {
      let coefficient = coefficients[rest]!
      if coefficient.isZero { continue }
      result.append(coefficient == Rational(1) ? rest : rest.scaled(by: coefficient))
    }
    if !constant.isZero { result.append(.number(constant)) }
    switch result.count {
    case 0: return .zero
    case 1: return result[0]
    default: return .sum(sorted(result))
    }
  }

  /// `(c, rest)` with `self == c × rest` and `rest` free of a leading number.
  private func splitCoefficient() -> (Rational, Expr) {
    if case .product(let factors) = self, case .number(let coefficient) = factors[0] {
      let rest = Array(factors.dropFirst())
      return (coefficient, rest.count == 1 ? rest[0] : .product(rest))
    }
    return (Rational(1), self)
  }

  /// `c × self` for a number `c` other than 0 and 1, where `self` is a product without a number or a single factor.
  private func scaled(by coefficient: Rational) -> Expr {
    if case .product(let factors) = self { return .product([.number(coefficient)] + factors) }
    return .product([.number(coefficient), self])
  }

  // MARK: Products

  /// The product of canonical expressions, in canonical form.
  static func makeProduct(_ factors: [Expr]) -> Expr {
    var coefficient = Rational(1)
    var bases: [Expr] = []
    var exponents: [Expr: Expr] = [:]

    func merge(_ base: Expr, _ exponent: Expr) {
      if let existing = exponents[base] {
        exponents[base] = makeSum([existing, exponent])
      } else {
        bases.append(base)
        exponents[base] = exponent
      }
    }
    func collect(_ factor: Expr) {
      switch factor {
      case .number(let value): coefficient *= value
      case .product(let inner): inner.forEach(collect)
      case .power(let base, let exponent): merge(base, exponent)
      default: merge(factor, .one)
      }
    }
    factors.forEach(collect)
    if coefficient.isZero { return .zero }

    // Rebuild each base with its merged exponent. A power may come back as a number, or as a number times radicals
    // (2^(5/4) is 2·2^(1/4)); those are taken apart again but not merged a second time, because the pieces are
    // already canonical and distinct.
    var rest: [Expr] = []
    func absorb(_ expression: Expr) {
      switch expression {
      case .number(let value): coefficient *= value
      case .product(let inner): inner.forEach(absorb)
      default: rest.append(expression)
      }
    }
    for base in bases {
      let exponent = exponents[base]!
      if exponent.isZero { continue }
      absorb(makePower(base, exponent))
    }
    if coefficient.isZero { return .zero }

    let sortedRest = sorted(rest)
    if sortedRest.isEmpty { return .number(coefficient) }
    if sortedRest.count == 1 {
      if coefficient == Rational(1) { return sortedRest[0] }
      // A number times a sum is spread over it: 2(x + 1) is 2x + 2.
      if case .sum(let terms) = sortedRest[0] {
        return makeSum(terms.map { makeProduct([.number(coefficient), $0]) })
      }
    }
    // Sums of plain numbers and radicals are multiplied out, so (1 + √2)(1 − √2) is −1. Sums with unknowns are left
    // as the user wrote them; expanding those is an explicit operation.
    if let expanded = expandedNumericProduct(coefficient: coefficient, factors: sortedRest) { return expanded }
    return .product(coefficient == Rational(1) ? sortedRest : [.number(coefficient)] + sortedRest)
  }

  /// The product multiplied out, when two or more factors are involved, one is a sum, and nothing has an unknown.
  private static func expandedNumericProduct(coefficient: Rational, factors: [Expr]) -> Expr? {
    guard factors.count >= 2, factors.contains(where: { if case .sum = $0 { return true } else { return false } }),
      factors.allSatisfy({ $0.freeSymbols.isEmpty })
    else { return nil }
    var terms: [Expr] = [.number(coefficient)]
    for factor in factors {
      let parts: [Expr]
      if case .sum(let inner) = factor { parts = inner } else { parts = [factor] }
      if terms.count * parts.count > maxExpandedTerms { return nil }
      var next: [Expr] = []
      for term in terms { for part in parts { next.append(makeProduct([term, part])) } }
      terms = next
    }
    return makeSum(terms)
  }

  /// Products and powers of sums with more terms than this are not multiplied out.
  private static let maxExpandedTerms = 400

  // MARK: Powers

  /// Numbers above this many bits are not computed exactly; the power stays as written and is approximated.
  private static let maxExactBits = NumberTheory.maxExactBits

  /// `base ^ exponent` for canonical operands whose base is not a zero meeting a non-positive power (callers check).
  static func makePower(_ base: Expr, _ exponent: Expr) -> Expr {
    if case .number(let n) = exponent {
      if n.isZero { return .one }
      if n == Rational(1) { return base }
    }
    switch base {
    case .number(let value):
      if value.isZero {
        if let n = exponent.rational, n.signum > 0 { return .zero }
        return .power(base, exponent)
      }
      if value == Rational(1) { return .one }
      if let n = exponent.rational { return numberPower(value, n) }
      if value.signum > 0, let split = splitNumericExponent(base: base, exponent: exponent) { return split }
      return .power(base, exponent)

    case .constant(let constant):
      if constant == .i { return imaginaryUnitPower(exponent) }
      if constant == .e {
        if case .function(.ln, let arguments) = exponent { return arguments[0] }  // e^(ln x) = x
        if let turn = eulerAngle(exponent), let exact = ExactTrigonometry.unitVector(ofTwelfths: turn) { return exact }
      }
      if let split = splitNumericExponent(base: base, exponent: exponent) { return split }
      return .power(base, exponent)

    case .power(let inner, let innerExponent):
      // (b^m)^n = b^(mn) for whole n, and for any n when b is positive; otherwise (x²)^(1/2) is |x|, not x.
      if exponent.isInteger || inner.isKnownPositive {
        return makePower(inner, makeProduct([innerExponent, exponent]))
      }
      return .power(base, exponent)

    case .product(let factors):
      if exponent.isInteger { return makeProduct(factors.map { makePower($0, exponent) }) }
      // A positive coefficient can always be taken out of a power: (4x)^(1/2) = 2 x^(1/2).
      if case .number(let coefficient) = factors[0], coefficient.signum > 0 {
        let rest = factors.count == 2 ? factors[1] : Expr.product(Array(factors.dropFirst()))
        return makeProduct([makePower(.number(coefficient), exponent), makePower(rest, exponent)])
      }
      if let root = complexHalfPower(of: base, exponent) { return root }  // √(−2i)
      return .power(base, exponent)

    case .sum(let terms):
      if let n = exponent.rational, n.isInteger, let whole = n.numerator.asInt, base.freeSymbols.isEmpty,
        let result = numericSumPower(terms, base: base, exponent: whole)
      {
        return result
      }
      if let root = complexHalfPower(of: base, exponent) { return root }
      // Take the numeric content out of the sum, so that (2x + 2)^-1 and (1/2)(x + 1)^-1 are one expression:
      // (c·s)^n = c^n · s^n for a positive number c.
      if exponent.rational != nil {
        let content = positiveContent(of: terms)
        if content != Rational(1) {
          let primitive = makeSum(terms.map { makeProduct([.number(content.reciprocal), $0]) })
          return makeProduct([makePower(.number(content), exponent), makePower(primitive, exponent)])
        }
      }
      return .power(base, exponent)

    case .symbol, .function:
      return .power(base, exponent)
    }
  }

  /// The positive rational `c` for which every term of the sum divided by `c` has a whole-number coefficient and
  /// those coefficients have no common factor: 2x + 2 gives 2, x/2 + 1/3 gives 1/6, 2e^11 − e^10/4 gives 1/4.
  private static func positiveContent(of terms: [Expr]) -> Rational {
    var numeratorGCD = BigInt(0)
    var denominatorLCM = BigInt(1)
    for term in terms {
      let coefficient: Rational
      if case .number(let value) = term { coefficient = value } else { coefficient = term.splitCoefficient().0 }
      numeratorGCD = BigInt.gcd(numeratorGCD, coefficient.numerator)
      denominatorLCM = denominatorLCM / BigInt.gcd(denominatorLCM, coefficient.denominator) * coefficient.denominator
    }
    return numeratorGCD.isZero ? Rational(1) : Rational(numeratorGCD, denominatorLCM)
  }

  /// `(a + b + …)^n` for a sum of plain numbers and radicals and a whole number `n`: multiplied out for positive
  /// `n`; for negative `n` the reciprocal is rationalised first when that is possible. `nil` leaves the power as is.
  private static func numericSumPower(_ terms: [Expr], base: Expr, exponent: Int) -> Expr? {
    if exponent == -1 {
      // 1/(a + bi) = (a − bi)/(a² + b²), whatever a and b are.
      if let (real, imaginary) = base.complexParts(), !imaginary.isZero {
        let norm = makeSum([makePower(real, .integer(2)), makePower(imaginary, .integer(2))])
        let conjugate = makeSum([real, makeProduct([.minusOne, imaginary, .i])])
        return makeProduct([conjugate, makePower(norm, .minusOne)])
      }
      guard terms.count == 2, let reciprocal = rationalizedReciprocal(terms[0], terms[1]) else { return nil }
      return reciprocal
    }
    if exponent < -1 {
      // S^-n is (S^n)^-1 with S^n multiplied out, so that it matches what reading "1/(S)^n" back produces.
      guard let positive = numericSumPower(terms, base: base, exponent: -exponent) else { return nil }
      return makePower(positive, .minusOne)
    }
    guard exponent <= 64 else { return nil }
    var result: Expr = .one
    var square = base
    var remaining = exponent
    while remaining > 0 {
      if remaining & 1 == 1 { result = multipliedOut(result, square) }
      remaining >>= 1
      if remaining > 0 { square = multipliedOut(square, square) }
      if result.nodeCount > 4000 || square.nodeCount > 4000 { return nil }
    }
    return result
  }

  /// `a × b` with every sum multiplied out term by term. Unlike `makeProduct` it never merges equal factors into a
  /// power, which for a sum would lead straight back to `numericSumPower`.
  static func multipliedOut(_ a: Expr, _ b: Expr) -> Expr {
    func terms(_ expression: Expr) -> [Expr] {
      if case .sum(let inner) = expression { return inner }
      return [expression]
    }
    var products: [Expr] = []
    for left in terms(a) { for right in terms(b) { products.append(makeProduct([left, right])) } }
    return makeSum(products)
  }

  /// `1 / (a + b)` as `(a − b) / (a² − b²)` when a² and b² are both rational (square roots and rationals), which
  /// removes the radicals from the denominator: 1/(1 + √2) is √2 − 1. `nil` when the terms are not of that kind.
  private static func rationalizedReciprocal(_ a: Expr, _ b: Expr) -> Expr? {
    guard case .number(let aSquared) = makePower(a, .integer(2)), case .number(let bSquared) = makePower(b, .integer(2))
    else { return nil }
    let norm = aSquared - bSquared
    if norm.isZero { return nil }
    return makeProduct([.number(norm.reciprocal), a - b])
  }

  /// For a positive base and an exponent `c + rest` with a numeric `c`: `base^c × base^rest` (2^(x+1) = 2·2^x).
  private static func splitNumericExponent(base: Expr, exponent: Expr) -> Expr? {
    guard case .sum(let terms) = exponent, case .number = terms[0] else { return nil }
    let remainder = makeSum(Array(terms.dropFirst()))
    // The two factors share a base, so `makeProduct` would merge them straight back into one power and split it
    // again without end. They are put together here without merging; merging them is what this split undoes.
    return joined([makePower(base, terms[0]), makePower(base, remainder)])
  }

  /// A product of canonical factors with the numbers multiplied together and the rest sorted, but with nothing merged
  /// or distributed.
  private static func joined(_ factors: [Expr]) -> Expr {
    var coefficient = Rational(1)
    var rest: [Expr] = []
    func absorb(_ factor: Expr) {
      switch factor {
      case .number(let value): coefficient *= value
      case .product(let inner): inner.forEach(absorb)
      default: rest.append(factor)
      }
    }
    factors.forEach(absorb)
    if coefficient.isZero { return .zero }
    let sortedRest = sorted(rest)
    if sortedRest.isEmpty { return .number(coefficient) }
    if coefficient == Rational(1) && sortedRest.count == 1 { return sortedRest[0] }
    return .product(coefficient == Rational(1) ? sortedRest : [.number(coefficient)] + sortedRest)
  }

  /// A rational to a rational power: exact when whole, otherwise an integer part times prime radicals.
  private static func numberPower(_ base: Rational, _ exponent: Rational) -> Expr {
    let unevaluated = Expr.power(.number(base), .number(exponent))
    if exponent.isInteger {
      guard let n = exponent.numerator.asInt else { return unevaluated }
      let bits = max(base.numerator.bitWidth, base.denominator.bitWidth)
      if n.magnitude > UInt(maxExactBits) || Int(n.magnitude) * bits > maxExactBits { return unevaluated }
      return .number(base.power(n))
    }
    if base.signum < 0 {
      // An odd root of a negative number is the real root: (−8)^(1/3) = −2. An even root is not real, and its principal
      // value is a^(p/q) · e^(iπp/q), which is exact for the angles the trigonometric tables cover.
      if exponent.denominator.isEven {
        guard let q = exponent.denominator.asInt, 12 % q == 0,
          let k = (exponent.numerator * BigInt(12 / q) % BigInt(24)).asInt,
          let direction = ExactTrigonometry.unitVector(ofTwelfths: k)
        else { return unevaluated }
        return makeProduct([numberPower(-base, exponent), direction])
      }
      let magnitude = numberPower(-base, exponent)
      return exponent.numerator.isEven ? magnitude : makeProduct([.minusOne, magnitude])
    }
    return radical(base, exponent) ?? unevaluated
  }

  /// `base^exponent` for a positive rational base and a non-integer rational exponent, as an integer part times
  /// prime radicals p^f with 0 < f < 1. Returns `nil` when the integer part would be too large to hold.
  private static func radical(_ base: Rational, _ exponent: Rational) -> Expr? {
    var coefficient = Rational(1)
    var atoms: [(prime: BigInt, exponent: Rational)] = []
    for (part, sign) in [(base.numerator, 1), (base.denominator, -1)] where !part.isOne {
      let factorization = NumberTheory.factor(part)
      var pieces = factorization.primes.map { ($0.prime, $0.exponent) }
      if !factorization.cofactor.isOne { pieces.append((factorization.cofactor, 1)) }
      for (prime, count) in pieces {
        let total = exponent * Rational(sign * count)
        let whole = total.numerator.floorDivided(by: total.denominator)
        guard let wholeInt = whole.asInt, wholeInt.magnitude * UInt(prime.bitWidth) <= UInt(maxExactBits) else {
          return nil
        }
        coefficient *= Rational(prime).power(wholeInt)
        let fraction = total - Rational(whole)
        if !fraction.isZero { atoms.append((prime, fraction)) }
      }
    }
    let radicals: [Expr] = atoms.sorted { $0.prime < $1.prime }
      .map { .power(.number(Rational($0.prime)), .number($0.exponent)) }
    if radicals.isEmpty { return .number(coefficient) }
    if coefficient == Rational(1) { return radicals.count == 1 ? radicals[0] : .product(radicals) }
    return .product([.number(coefficient)] + radicals)
  }

  // MARK: The imaginary unit

  /// `i` to a power: i, −1, −i, 1 in turn for whole exponents; i^(p/q) is exact when 6p/q is whole (e^(iπ/2 · p/q)).
  private static func imaginaryUnitPower(_ exponent: Expr) -> Expr {
    guard let n = exponent.rational else { return .power(.i, exponent) }
    if n.isInteger {
      var remainder = (n.numerator % BigInt(4)).asInt ?? 0
      if remainder < 0 { remainder += 4 }
      switch remainder {
      case 0: return .one
      case 1: return .i
      case 2: return .minusOne
      default: return makeProduct([.minusOne, .i])
      }
    }
    let sixths = n * Rational(6)
    if sixths.isInteger, let k = (sixths.numerator % BigInt(24)).asInt,
      let direction = ExactTrigonometry.unitVector(ofTwelfths: k)
    {
      return direction
    }
    return .power(.i, exponent)
  }

  /// `k` when the expression is `k·π·i/12` for a whole number `k`, which is the angle (in twelfths of π) of e^(that).
  private static func eulerAngle(_ exponent: Expr) -> Int? {
    var coefficient = Rational(1)
    var rest = exponent
    if case .product(let factors) = exponent, case .number(let number) = factors[0] {
      coefficient = number
      rest = factors.count == 2 ? factors[1] : .product(Array(factors.dropFirst()))
    }
    guard case .product(let parts) = rest, parts == [.pi, .i] else { return nil }
    let twelfths = coefficient * Rational(12)
    guard twelfths.isInteger else { return nil }
    return (twelfths.numerator % BigInt(24)).asInt
  }

  /// `(real, imaginary)` with `self = real + imaginary·i` and neither part containing `i`, when `i` occurs only as a
  /// factor of whole terms (as in `3 + 2i` or `√2 i`); `nil` when it is inside a function or a power.
  func complexParts() -> (real: Expr, imaginary: Expr)? {
    var realTerms: [Expr] = []
    var imaginaryTerms: [Expr] = []
    let terms: [Expr]
    if case .sum(let inner) = self { terms = inner } else { terms = [self] }
    for term in terms {
      if !term.containsImaginaryUnit {
        realTerms.append(term)
      } else if term == .i {
        imaginaryTerms.append(.one)
      } else if case .product(let factors) = term, let position = factors.firstIndex(of: .i) {
        var rest = factors
        rest.remove(at: position)
        if rest.contains(where: \.containsImaginaryUnit) { return nil }
        imaginaryTerms.append(Expr.makeProduct(rest))
      } else {
        return nil
      }
    }
    return (Expr.makeSum(realTerms), Expr.makeSum(imaginaryTerms))
  }

  /// The principal square root of `a + bi` for real numbers `a` and `b` written with radicals, when it is a simpler
  /// expression than the root itself: `√(3 + 4i)` is `2 + i`, `√(2i)` is `1 + i`. The formula is
  /// `√((|z| + a)/2) + i·sign(b)·√((|z| − a)/2)` with `|z| = √(a² + b²)`; it is used only when both inner roots come out
  /// without a root of a sum left in them.
  private static func complexSquareRoot(of base: Expr) -> Expr? {
    guard base.freeSymbols.isEmpty, base.containsImaginaryUnit, let (real, imaginary) = base.complexParts(),
      !imaginary.isZero, let sign = imaginary.numericSign
    else { return nil }
    let modulus = makePower(
      makeSum([makePower(real, .integer(2)), makePower(imaginary, .integer(2))]), .fraction(1, 2))
    let half = Expr.number(Rational(1, 2))
    let first = makePower(makeProduct([half, makeSum([modulus, real])]), .fraction(1, 2))
    let second = makePower(makeProduct([half, makeSum([modulus, makeProduct([.minusOne, real])])]), .fraction(1, 2))
    guard !first.hasRootOfSum, !second.hasRootOfSum else { return nil }
    return makeSum([first, makeProduct([.number(Rational(sign)), second, .i])])
  }

  /// `base^(p/2)` for an odd whole `p` and a complex base whose square root is simple: `(√z)^p`. Writing it this way for
  /// every `p` keeps `z^(−1/2)` and `1/√z`, which mean the same, one expression.
  private static func complexHalfPower(of base: Expr, _ exponent: Expr) -> Expr? {
    guard let n = exponent.rational, n.denominator == BigInt(2), let root = complexSquareRoot(of: base) else {
      return nil
    }
    return makePower(root, .number(Rational(n.numerator)))
  }

  /// Whether a real number with no unknown is positive (1), negative (−1) or zero (0), judged from its decimal value.
  var numericSign: Int? {
    guard freeSymbols.isEmpty, let value = try? approximation(precision: 30) else { return nil }
    if value.isZero { return 0 }
    return value.isNegative ? -1 : 1
  }

  /// Whether a square root (or other fractional power) of a sum occurs anywhere in the expression.
  var hasRootOfSum: Bool {
    switch self {
    case .number, .constant, .symbol: return false
    case .power(let base, let exponent):
      if case .sum = base, exponent.rational?.isInteger != true { return true }
      return base.hasRootOfSum || exponent.hasRootOfSum
    case .sum(let parts), .product(let parts), .function(_, let parts): return parts.contains { $0.hasRootOfSum }
    }
  }

  // MARK: Properties used by the rules

  var isInteger: Bool { rational?.isInteger ?? false }

  /// True when the expression is certainly a positive real number.
  var isKnownPositive: Bool {
    switch self {
    case .number(let value): return value.signum > 0
    case .constant(let constant): return constant != .i
    case .power(let base, _): return base.isKnownPositive
    case .product(let factors), .sum(let factors): return factors.allSatisfy { $0.isKnownPositive }
    case .symbol, .function: return false
    }
  }
}

extension Expr {
  /// The same expression rebuilt from its parts through the smart constructors. For a canonical expression this is
  /// the identity, which the tests use to check that the canonical form is stable.
  func rebuilt() throws(MathError) -> Expr {
    switch self {
    case .number, .constant, .symbol: return self
    case .sum(let terms):
      var rebuilt: [Expr] = []
      for term in terms { rebuilt.append(try term.rebuilt()) }
      return Expr.makeSum(rebuilt)
    case .product(let factors):
      var rebuilt: [Expr] = []
      for factor in factors { rebuilt.append(try factor.rebuilt()) }
      return Expr.makeProduct(rebuilt)
    case .power(let base, let exponent): return try base.rebuilt().raised(to: exponent.rebuilt())
    case .function(let function, let arguments):
      var rebuilt: [Expr] = []
      for argument in arguments { rebuilt.append(try argument.rebuilt()) }
      return try Expr.apply(function, rebuilt)
    }
  }
}
