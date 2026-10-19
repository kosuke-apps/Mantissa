/// A polynomial or a fraction of polynomials in one unknown written as a product: `2(x + 1)(x − 3)²`, `(x + 1)/(x − 2)`.
///
/// The canonical form of an expression keeps a numeric coefficient spread over a sum (`2(x + 1)` is `2x + 2`), so a factored
/// form is a value of its own that is only displayed. The factors are the linear ones with rational roots, each with integer
/// coefficients, and whatever polynomial is left over after them (which may still factor, but not over the rationals by a
/// root).
public struct Factorization: Sendable, Equatable {
  public struct Factor: Sendable, Equatable {
    /// A polynomial with whole-number coefficients and a positive leading coefficient (`x`, `2x - 3`, `x^2 + x + 1`).
    public var base: Expr
    public var power: Int
  }

  /// The number in front of the factors; it may be a fraction or negative.
  public var coefficient: Rational
  public var numerator: [Factor]
  public var denominator: [Factor]
  /// Whether factors of the numerator and the denominator were cancelled: `(x² − 1)/(x − 1)` is `x + 1`.
  public var cancelled: Bool
  /// Whether the expression was a sum of fractions, which this writes as one fraction (`1/x + 1/y` is `(x + y)/(xy)`).
  public var combinesFractions = false
  /// Whether the factors are what the terms of a sum have in common (`eˣ(x − 1)`), not the factors of a polynomial.
  public var isCommonFactor = false

  /// The value as an expression: the factors multiplied together, with the factors of the denominator to negative powers.
  /// The factors are not multiplied out.
  public var expression: Expr {
    var factors: [Expr] = [.number(coefficient)]
    for factor in numerator { factors.append(Expr.makePower(factor.base, .integer(factor.power))) }
    for factor in denominator { factors.append(Expr.makePower(factor.base, .integer(-factor.power))) }
    return Expr.makeProduct(factors)
  }

  /// Whether it says anything more than a single factor to the first power: the expression itself.
  var isTrivial: Bool {
    !cancelled && denominator.isEmpty && numerator.count <= 1 && (numerator.first?.power ?? 1) == 1
      && (coefficient == Rational(1) || numerator.isEmpty)
  }
}

extension Expr {
  /// The expression as a product of factors, when it is a polynomial or a fraction of polynomials in one or several unknowns
  /// with rational coefficients; `nil` otherwise.
  public func factorization() -> Factorization? {
    guard nodeCount <= 400, !freeSymbols.isEmpty else { return nil }
    guard var result = freeSymbols.count > 1 ? severalUnknownsFactorization() : singleUnknownFactorization() else {
      return nil
    }
    if case .sum(let terms) = self, terms.contains(where: { $0.hasNegativePower }) { result.combinesFractions = true }
    return result
  }

  private var hasNegativePower: Bool {
    !collectAll(where: { part in
      if case .power(_, let exponent) = part, exponent.rational?.isNegative == true { return true }
      return false
    }).isEmpty
  }

  private func singleUnknownFactorization() -> Factorization? {
    guard let variable = freeSymbols.first else { return nil }
    guard let (numerator, denominators) = together(variable: variable),
      let top = numerator.polynomial(in: variable)?.rationalCoefficients, !top.isEmpty
    else { return nil }
    var bottom = Expr.one
    for (base, power) in denominators { bottom = bottom * Expr.makePower(base, .integer(power)) }
    guard let bottomCoefficients = bottom.expanded().polynomial(in: variable)?.rationalCoefficients,
      !bottomCoefficients.isEmpty
    else { return nil }

    var (upperCoefficient, upper) = Factoring.factor(RationalPolynomial(top), variable)
    var (lowerCoefficient, lower) = Factoring.factor(RationalPolynomial(bottomCoefficients), variable)
    _ = (upperCoefficient, lowerCoefficient)

    // Cancel what both have.
    var cancelled = false
    for index in upper.indices {
      guard let other = lower.firstIndex(where: { $0.base == upper[index].base }) else { continue }
      let common = min(upper[index].power, lower[other].power)
      upper[index].power -= common
      lower[other].power -= common
      if common > 0 { cancelled = true }
    }
    upper.removeAll { $0.power == 0 }
    lower.removeAll { $0.power == 0 }
    return Factorization(
      coefficient: upperCoefficient / lowerCoefficient, numerator: upper, denominator: lower, cancelled: cancelled)
  }
}

extension Expr {
  /// The same for a polynomial or a fraction of polynomials in several unknowns (`(a² − b²)/(a − b)` is `a + b`).
  private func severalUnknownsFactorization() -> Factorization? {
    let names = freeSymbols.sorted()
    guard names.count <= 4, let (numerator, denominators) = together(variables: freeSymbols) else { return nil }
    var bottom = Expr.one
    for (base, power) in denominators { bottom = bottom * Expr.makePower(base, .integer(power)) }
    let ring = PolynomialRing(names: names, budget: Factoring.workBudget)
    guard let top = MultiPolynomial(numerator, ring: ring), !top.isZero, top.terms.count <= 80,
      let low = MultiPolynomial(bottom, ring: ring), !low.isZero, low.terms.count <= 80
    else { return nil }

    let (upperCoefficient, upper) = top.factored()
    let (lowerCoefficient, lower) = low.factored()
    // A polynomial that took more work than that is left as it is.
    guard !ring.isExhausted else { return nil }
    var numeratorFactors = upper
    var denominatorFactors = lower
    var cancelled = false
    for index in numeratorFactors.indices {
      guard let other = denominatorFactors.firstIndex(where: { $0.base == numeratorFactors[index].base }) else {
        continue
      }
      let common = min(numeratorFactors[index].power, denominatorFactors[other].power)
      numeratorFactors[index].power -= common
      denominatorFactors[other].power -= common
      if common > 0 { cancelled = true }
    }

    func factors(_ list: [(base: MultiPolynomial, power: Int)]) -> [Factorization.Factor] {
      list.filter { $0.power > 0 }
        .sorted { Factoring.reads($0.base, before: $1.base) }
        .map { Factorization.Factor(base: $0.base.expression, power: $0.power) }
    }
    var result = Factorization(
      coefficient: upperCoefficient / lowerCoefficient, numerator: factors(numeratorFactors),
      denominator: factors(denominatorFactors), cancelled: cancelled)
    // −(x − y) reads better as y − x.
    if result.coefficient == Rational(-1), result.numerator.count == 1, result.numerator[0].power == 1,
      let flipped = numeratorFactors.first(where: { $0.power > 0 })?.base, flipped.terms.count == 2,
      flipped.terms.values.contains(where: { $0.isNegative })
    {
      result.coefficient = Rational(1)
      result.numerator[0].base = (-flipped).expression
    }
    return result
  }
}

extension Expr {
  /// A sum with a factor in every term, written as that factor times the rest: `x eˣ − eˣ` is `eˣ(x − 1)`, `x ln x − x` is
  /// `x(ln x − 1)`, and a number that divides every coefficient comes out too. The factors are whatever is the same in all
  /// terms: a function, a power of the unknown with the least exponent, an exponential. `nil` when there is none.
  func commonFactorization() -> Factorization? {
    guard case .sum(let terms) = self, terms.count >= 2 else { return nil }
    typealias Part = (coefficient: Rational, factors: [(base: Expr, exponent: Rational)])

    func split(_ term: Expr) -> Part {
      var coefficient = Rational(1)
      var factors: [(base: Expr, exponent: Rational)] = []
      func add(_ base: Expr, _ exponent: Rational) {
        if let index = factors.firstIndex(where: { $0.base == base }) {
          factors[index].exponent += exponent
        } else {
          factors.append((base, exponent))
        }
      }
      let list: [Expr]
      if case .product(let inner) = term { list = inner } else { list = [term] }
      for factor in list {
        switch factor {
        case .number(let value): coefficient *= value
        case .power(let base, let exponent):
          if let n = exponent.rational { add(base, n) } else { add(factor, Rational(1)) }
        default: add(factor, Rational(1))
        }
      }
      return (coefficient, factors)
    }
    let parts = terms.map(split)

    // The number: the greatest common divisor of the numerators over the least common multiple of the denominators.
    var numeratorGCD = BigInt(0)
    var denominatorLCM = BigInt(1)
    for part in parts {
      numeratorGCD = BigInt.gcd(numeratorGCD, part.coefficient.numerator.magnitude)
      denominatorLCM =
        denominatorLCM / BigInt.gcd(denominatorLCM, part.coefficient.denominator)
        * part.coefficient.denominator
    }
    guard !numeratorGCD.isZero else { return nil }
    var content = Rational(numeratorGCD, denominatorLCM)
    if parts.allSatisfy({ $0.coefficient.isNegative }) { content = -content }

    // What every term has: the same base with a positive exponent in each, to the least of them.
    var common: [(base: Expr, exponent: Rational)] = []
    for (base, _) in parts[0].factors {
      var least: Rational?
      for part in parts {
        guard let exponent = part.factors.first(where: { $0.base == base })?.exponent, exponent.signum > 0 else {
          least = nil
          break
        }
        least = least.map { min($0, exponent) } ?? exponent
      }
      if let least { common.append((base, least)) }
    }
    guard !common.isEmpty || (content != Rational(1) && content != Rational(-1)) else { return nil }

    var rest: [Expr] = []
    for part in parts {
      var factors: [Expr] = [.number(part.coefficient / content)]
      for (base, exponent) in part.factors {
        let taken = common.first(where: { $0.base == base })?.exponent ?? Rational(0)
        if exponent != taken { factors.append(Expr.makePower(base, .number(exponent - taken))) }
      }
      rest.append(Expr.makeProduct(factors))
    }
    var numerator = common.map { Factorization.Factor(base: Expr.makePower($0.base, .number($0.exponent)), power: 1) }
    numerator.append(Factorization.Factor(base: Expr.makeSum(rest), power: 1))
    var result = Factorization(coefficient: content, numerator: numerator, denominator: [], cancelled: false)
    result.isCommonFactor = true
    return result
  }
}

enum Factoring {
  /// How much work the factoring of the polynomials of one expression may take, in the units of `PolynomialRing`.
  static let workBudget = 100_000

  /// `p = coefficient · Π factorᵖᵒʷᵉʳ`.
  static func factor(_ polynomial: RationalPolynomial, _ variable: String) -> (Rational, [Factorization.Factor]) {
    guard polynomial.degree >= 0 else { return (Rational(0), []) }
    if polynomial.degree == 0 { return (polynomial[0], []) }

    let x = Expr.symbol(variable)
    var rest = RationalPolynomial(primitive(polynomial))
    var factors: [(polynomial: RationalPolynomial, expression: Expr, order: Rational, power: Int)] = []

    var zeros = 0
    while rest.degree >= 1, rest[0].isZero {
      rest = RationalPolynomial(Array(rest.coefficients.dropFirst()))
      zeros += 1
    }
    if zeros > 0 { factors.append((RationalPolynomial([Rational(0), Rational(1)]), x, Rational(0), zeros)) }

    while rest.degree >= 1 {
      let (roots, remaining) = rest.rationalRoots()
      if roots.isEmpty { break }
      for root in roots {
        let a = root.numerator
        let b = root.denominator
        let line = RationalPolynomial([Rational(-a), Rational(b)])
        let expression = Expr.makeSum([Expr.makeProduct([.number(Rational(b)), x]), .number(Rational(-a))])
        if let index = factors.firstIndex(where: { $0.polynomial == line }) {
          factors[index].power += 1
        } else {
          factors.append((line, expression, root, 1))
        }
      }
      rest = remaining
    }
    // The unknown itself first, then the roots nearest zero (x(x + 1)(x + 2)), a negative root before a positive one of the same
    // size: x(x + 1)(x − 1).
    factors.sort { a, b in
      let (aZero, bZero) = (a.order.isZero, b.order.isZero)
      if aZero != bZero { return aZero }
      if a.order.magnitude != b.order.magnitude { return a.order.magnitude < b.order.magnitude }
      return a.order < b.order
    }

    var result: [Factorization.Factor] = factors.map { .init(base: $0.expression, power: $0.power) }
    var product = RationalPolynomial([Rational(1)])
    for factor in factors { for _ in 0..<factor.power { product = multiply(product, factor.polynomial) } }
    if rest.degree >= 1 {
      // What has no rational root may still be a product of polynomials of higher degree: x⁴ + 4 is (x² + 2x + 2)(x² − 2x + 2).
      for piece in rest.factorsWithoutRoots() {
        result.append(.init(base: expression(of: piece, variable), power: 1))
        product = multiply(product, piece)
      }
    }
    return (polynomial.leading / product.leading, result)
  }

  /// Whether a factor is written before another: the smaller one, then the one with fewer terms, then the one whose
  /// coefficients come first (`a − b` before `a + b`).
  static func reads(_ a: MultiPolynomial, before b: MultiPolynomial) -> Bool {
    func key(_ polynomial: MultiPolynomial) -> (Int, Int, [Double]) {
      (
        polynomial.totalDegree, polynomial.terms.count,
        polynomial.sortedTerms.map { Double($0.coefficient.numerator.description) ?? 0 }
      )
    }
    let (left, right) = (key(a), key(b))
    if left.0 != right.0 { return left.0 < right.0 }
    if left.1 != right.1 { return left.1 < right.1 }
    if left.2 != right.2 { return left.2.lexicographicallyPrecedes(right.2) }
    // The same shape: the one with the earlier unknown first, a before b.
    return (b.leadingMonomial ?? []).lexicographicallyPrecedes(a.leadingMonomial ?? [])
  }

  /// The polynomial with whole-number coefficients with no common factor and a positive leading coefficient.
  private static func primitive(_ polynomial: RationalPolynomial) -> [Rational] {
    var integers = polynomial.primitiveIntegerCoefficients
    if let leading = integers.last, leading.isNegative { integers = integers.map { -$0 } }
    return integers.map { Rational($0) }
  }

  private static func expression(of polynomial: RationalPolynomial, _ variable: String) -> Expr {
    Expr.makeSum(
      polynomial.coefficients.enumerated().map { power, coefficient in
        Expr.makeProduct([.number(coefficient), Expr.makePower(.symbol(variable), .integer(power))])
      })
  }

  private static func multiply(_ a: RationalPolynomial, _ b: RationalPolynomial) -> RationalPolynomial {
    guard !a.isZero, !b.isZero else { return RationalPolynomial([]) }
    var result = Array(repeating: Rational(0), count: a.degree + b.degree + 1)
    for i in 0...a.degree { for j in 0...b.degree { result[i + j] += a[i] * b[j] } }
    return RationalPolynomial(result)
  }
}

/// Another way of writing an answer that has an unknown in it.
public enum ExpressionForm: Sendable, Equatable {
  /// Products and powers of sums multiplied out.
  case expanded(Expr)
  /// As a product of factors, or a fraction of them with common factors cancelled.
  case factored(Factorization)
  /// A sum of fractions in several unknowns written as one fraction (`1/x + 1/y` is `(x + y)/(xy)`).
  case combined(Expr)
}

extension Expr {
  /// A sum with fractions in it as one fraction over the product of its denominators, for any number of unknowns; `nil` when there
  /// is no fraction, or when the one fraction is not smaller.
  func combinedOverAllDenominators() -> Expr? {
    guard case .sum = self, let (numerator, denominators) = together(variables: freeSymbols), !denominators.isEmpty
    else { return nil }
    var factors = [numerator]
    for (base, power) in denominators { factors.append(Expr.makePower(base, .integer(-power))) }
    let combined = Expr.makeProduct(factors)
    return combined.nodeCount <= nodeCount + 4 ? combined : nil
  }

  /// The expanded and the factored form of an expression with an unknown, for those that say something the expression does not.
  public func otherForms() -> [ExpressionForm] {
    guard !freeSymbols.isEmpty, nodeCount <= 200 else { return [] }
    var forms: [ExpressionForm] = []
    let shown = Typesetter.nodes(for: self).parserText

    // Multiplying out is for products and powers; a fraction is better as one fraction (see `factorization`).
    let hasDenominator = !collectAll(where: { part in
      if case .power(_, let exponent) = part, exponent.rational?.isNegative == true { return true }
      return false
    }).isEmpty
    let expanded = self.expanded().trigonometricallyTidied()
    if !hasDenominator, expanded != self, expanded.nodeCount <= 400 { forms.append(.expanded(expanded)) }

    if let factorization = factorization(), !factorization.isTrivial,
      Typesetter.nodes(for: factorization).parserText != shown
    {
      // Where it is the same as the expanded form there is nothing to add.
      forms.append(.factored(factorization))
    } else if freeSymbols.count > 1, let combined = combinedOverAllDenominators(), combined != self,
      Typesetter.nodes(for: combined).parserText != shown
    {
      forms.append(.combined(combined))
    } else if let common = commonFactorization(), Typesetter.nodes(for: common).parserText != shown {
      forms.append(.factored(common))
    }
    return forms
  }
}
