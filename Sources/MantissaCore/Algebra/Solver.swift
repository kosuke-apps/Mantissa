/// One solution: its exact form when there is one, and its value as a decimal when it is a number (a solution that
/// contains another letter, `−b/a`, has none).
public struct SolvedValue: Sendable, Equatable {
  public var exact: Expr?
  public var approximation: ComplexDecimal?

  public init(exact: Expr?, approximation: ComplexDecimal?) {
    self.exact = exact
    self.approximation = approximation
  }

  /// Whether the value is a real number (`false` when it is not a number at all).
  public var isReal: Bool { approximation?.isReal ?? false }
}

/// What solving an equation or a system came to.
public enum Solved: Sendable, Equatable {
  /// A statement with no unknowns: `1 + 1 = 2`.
  case truth(Bool)
  /// An equation that every value of the unknown satisfies, except those where something is not defined.
  case everything(variable: String, excluding: [SolvedValue])
  /// An equation no value of the unknown satisfies.
  case none(variable: String)
  /// The values of the unknown that satisfy the equation, real ones first in increasing order.
  case values(variable: String, [SolvedValue])
}

/// Solves one equation in one unknown, treating any other letters as constants.
enum EquationSolver {
  /// The unknown to solve for: `x` if it is there, then `y`, `z`, and otherwise the first letter alphabetically.
  static func unknown(in symbols: Set<String>) -> String? {
    for preferred in ["x", "y", "z"] where symbols.contains(preferred) { return preferred }
    return symbols.sorted().first
  }

  /// Solves `expression = 0` for `variable`. `nil` when the equation is not of a kind this solver handles.
  static func solve(_ expression: Expr, for variable: String) -> Solved? {
    guard let (numerator, denominators) = expression.together(variable: variable),
      let polynomial = numerator.polynomial(in: variable)
    else { return nil }

    // Where a denominator is zero the expression is not defined, so those values are not solutions.
    let excluded = denominators.compactMap { $0.base.polynomial(in: variable) }
    guard excluded.count == denominators.count else { return nil }

    if polynomial.isZero {
      guard let values = excludedValues(excluded, variable: variable) else { return nil }
      return .everything(variable: variable, excluding: values)
    }
    if polynomial.degree == 0 { return .none(variable: variable) }

    guard var candidates = roots(of: polynomial) else { return nil }
    candidates = candidates.filter { candidate in !excluded.contains { vanishes($0, at: candidate) } }
    candidates = sortedAndDistinct(candidates)
    return candidates.isEmpty ? .none(variable: variable) : .values(variable: variable, candidates)
  }

  // MARK: Roots

  /// The roots of a polynomial in one unknown, or `nil` if its coefficients are beyond this solver (an unknown letter in a
  /// polynomial of degree above 2).
  private static func roots(of polynomial: Polynomial) -> [SolvedValue]? {
    if let rational = polynomial.rationalCoefficients {
      let solved = PolynomialRoots.solve(RationalPolynomial(rational))
      return solved.exact.compactMap(value(of:)) + solved.numeric.map { SolvedValue(exact: nil, approximation: $0) }
    }
    let c = polynomial.coefficients
    switch polynomial.degree {
    case 1:
      guard let root = try? (-c[0]).divided(by: c[1]) else { return nil }
      return [value(of: root)].compactMap { $0 }
    case 2:
      return quadratic(c[2], c[1], c[0]).compactMap(value(of:))
    default:
      return nil
    }
  }

  /// `a x² + b x + c` for expression coefficients: `(−b ± √(b² − 4ac)) / 2a`.
  private static func quadratic(_ a: Expr, _ b: Expr, _ c: Expr) -> [Expr] {
    let discriminant = (b * b - Expr.integer(4) * a * c).expanded()
    guard let scale = try? Expr.one.divided(by: Expr.integer(2) * a) else { return [] }
    if discriminant.isZero { return [(-b) * scale] }
    let root = Expr.makePower(discriminant, .fraction(1, 2))
    return [(-b + root) * scale, (-b - root) * scale]
  }

  private static func value(of exact: Expr) -> SolvedValue? {
    if let real = try? exact.approximation(precision: 50) {
      return SolvedValue(exact: exact, approximation: ComplexDecimal(real: real))
    }
    if let complex = try? exact.complexApproximation(precision: 50) {
      return SolvedValue(exact: exact, approximation: complex)
    }
    // A value with another letter in it has no decimal.
    return exact.freeSymbols.isEmpty ? nil : SolvedValue(exact: exact, approximation: nil)
  }

  // MARK: Excluded values

  private static func excludedValues(_ polynomials: [Polynomial], variable: String) -> [SolvedValue]? {
    var values: [SolvedValue] = []
    for polynomial in polynomials {
      guard let found = roots(of: polynomial) else { return nil }
      values += found
    }
    return sortedAndDistinct(values)
  }

  /// Whether the polynomial is zero at the value (for a value that is only known as a decimal, to within rounding).
  private static func vanishes(_ polynomial: Polynomial, at value: SolvedValue) -> Bool {
    if let exact = value.exact {
      var terms: [Expr] = []
      for (power, coefficient) in polynomial.coefficients.enumerated() {
        guard let term = try? coefficient * exact.raised(to: .integer(power)) else { return false }
        terms.append(term)
      }
      let total = Expr.makeSum(terms)
      if total.isZero { return true }
      if total.freeSymbols.isEmpty, let size = try? total.complexApproximation(precision: 40) {
        return (size.magnitudeSquared.decimalOrder ?? Int.min) < -60
      }
      return false
    }
    guard let point = value.approximation,
      let coefficients = try? polynomial.coefficients.map({ try $0.complexApproximation(precision: 40) })
    else { return false }
    var total = ComplexDecimal(real: BigDecimal(0))
    for coefficient in coefficients.reversed() {
      total = total.multiplied(by: point, precision: 40).adding(coefficient, precision: 40)
    }
    return (total.magnitudeSquared.decimalOrder ?? Int.min) < -40
  }

  // MARK: Ordering

  /// Real values in increasing order, then the other numbers by real and imaginary part, then values that are not numbers
  /// as they came; values equal to within rounding appear once.
  static func sortedAndDistinct(_ values: [SolvedValue]) -> [SolvedValue] {
    let numbers = values.filter { $0.approximation != nil }
    let symbolic = values.filter { $0.approximation == nil }
    let sorted = numbers.sorted { a, b in
      let (x, y) = (a.approximation!, b.approximation!)
      if x.isReal != y.isReal { return x.isReal }
      if x.real != y.real { return x.real < y.real }
      return x.imaginary < y.imaginary
    }
    var result: [SolvedValue] = []
    for value in sorted {
      let z = value.approximation!
      let duplicate = result.contains { other in
        let w = other.approximation!
        let scale = max(BigDecimal(1), z.real.magnitude, z.imaginary.magnitude)
        let tolerance = scale * BigDecimal(BigInt(1), exponent: -30)
        return (w.real - z.real).magnitude <= tolerance && (w.imaginary - z.imaginary).magnitude <= tolerance
      }
      if !duplicate { result.append(value) }
    }
    for value in symbolic where !result.contains(where: { $0.exact == value.exact }) { result.append(value) }
    return result
  }
}

extension Calculator {
  /// Solves an equation. The unknown is `x` if the equation has one, otherwise `y`, `z` or the first letter in the
  /// alphabet; other letters are treated as constants. An input that is not an equation, or one of a kind that cannot be
  /// solved yet, is `CalculatorError.unsupported`.
  public func solve(_ text: String) throws(CalculatorError) -> Solved {
    let statement: Statement
    do {
      statement = try Parser.parse(text)
    } catch {
      throw .parse(error)
    }
    guard case .relation(let chain) = statement, chain.links.count == 1, chain.links[0].op == .equal else {
      throw .unsupported(.equation)
    }
    let builder = Builder(angleUnit: settings.angleUnit)
    let left: Expr
    let right: Expr
    do {
      left = try builder.build(chain.first)
      right = try builder.build(chain.links[0].operand)
    } catch {
      throw .math(error)
    }
    // `y = f(x)` defines a function (it is drawn, not solved); `y = x²` is not an equation to solve for x.
    let definesFunction =
      (chain.first == .symbol("y") && right.freeSymbols.isSubset(of: ["x"]))
      || (chain.links[0].operand == .symbol("y") && left.freeSymbols.isSubset(of: ["x"]))
    if definesFunction { throw .unsupported(.equation) }
    let difference = left - right

    // The unknown is looked for in what was typed, not in the difference, so that `x + 1 = x` (which has none left after
    // subtracting) is an equation with no solution and not a false statement.
    let letters = left.freeSymbols.union(right.freeSymbols)
    guard let variable = EquationSolver.unknown(in: letters) else {
      return .truth(isZero(difference))
    }
    guard let solved = EquationSolver.solve(difference, for: variable) else { throw .unsupported(.equation) }
    return solved
  }

  /// Whether a number with no unknowns is zero: exactly when the canonical form says so, otherwise when its decimal value
  /// is zero to 40 digits.
  private func isZero(_ value: Expr) -> Bool {
    if value.isZero { return true }
    if let real = try? value.approximation(precision: 40) { return (real.decimalOrder ?? Int.min) < -35 }
    if let complex = try? value.complexApproximation(precision: 40) {
      return (complex.magnitudeSquared.decimalOrder ?? Int.min) < -70
    }
    return false
  }
}
