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

  /// Whether it says anything more than a single factor to the first power: the expression itself.
  var isTrivial: Bool {
    !cancelled && denominator.isEmpty && numerator.count <= 1 && (numerator.first?.power ?? 1) == 1
      && (coefficient == Rational(1) || numerator.isEmpty)
  }
}

extension Expr {
  /// The expression as a product of factors, when it is a polynomial or a fraction of polynomials in one unknown with rational
  /// coefficients; `nil` otherwise.
  public func factorization() -> Factorization? {
    guard freeSymbols.count == 1, let variable = freeSymbols.first, nodeCount <= 400 else { return nil }
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

enum Factoring {
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
      let normalized = RationalPolynomial(primitive(rest))
      result.append(.init(base: expression(of: normalized, variable), power: 1))
      product = multiply(product, normalized)
    }
    return (polynomial.leading / product.leading, result)
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
    let expanded = self.expanded()
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
    }
    return forms
  }
}
