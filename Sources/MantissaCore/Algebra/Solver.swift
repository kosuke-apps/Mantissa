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

  /// An exact value with its decimal, when it has one. `nil` when the value is a number that cannot be evaluated.
  static func exact(_ value: Expr) -> SolvedValue? {
    if let real = try? value.approximation(precision: 50) {
      return SolvedValue(exact: value, approximation: ComplexDecimal(real: real))
    }
    if let complex = try? value.complexApproximation(precision: 50) {
      return SolvedValue(exact: value, approximation: complex)
    }
    // A value with another letter in it has no decimal.
    return value.freeSymbols.isEmpty ? nil : SolvedValue(exact: value, approximation: nil)
  }
}

/// One end of an interval: where it is, and whether the point itself belongs to the interval.
public struct SolvedBound: Sendable, Equatable {
  public var value: SolvedValue
  public var isClosed: Bool

  public init(value: SolvedValue, isClosed: Bool) {
    self.value = value
    self.isClosed = isClosed
  }
}

/// A stretch of the real line. An end that is `nil` goes on forever. A single point is an interval closed at both ends
/// with the same value.
public struct SolvedInterval: Sendable, Equatable {
  public var lower: SolvedBound?
  public var upper: SolvedBound?

  public init(lower: SolvedBound?, upper: SolvedBound?) {
    self.lower = lower
    self.upper = upper
  }

  /// Whether the interval is one point.
  public var isPoint: Bool {
    guard let lower, let upper, lower.isClosed, upper.isClosed else { return false }
    return lower.value.exact == upper.value.exact && lower.value.approximation == upper.value.approximation
  }
}

/// The value one unknown takes.
public struct Assignment: Sendable, Equatable {
  public var variable: String
  public var value: SolvedValue

  public init(variable: String, value: SolvedValue) {
    self.variable = variable
    self.value = value
  }
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
  /// The values of the unknown that satisfy an inequality: a union of separate intervals, in increasing order.
  case intervals(variable: String, [SolvedInterval])
  /// The solutions of a system: each is a value for every unknown, in the order of `variables`.
  case tuples(variables: [String], [[SolvedValue]])
  /// A system with infinitely many solutions: the unknowns that are determined, given in terms of the `free` ones, which
  /// can be anything.
  case dependent([Assignment], free: [String])
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
  static func roots(of polynomial: Polynomial) -> [SolvedValue]? {
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

  private static func value(of exact: Expr) -> SolvedValue? { SolvedValue.exact(exact) }

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

extension Expr {
  /// Whether the expression is zero: exactly when the canonical form says so, and for a number with no unknowns also when
  /// its decimal value is zero to 40 digits (`sin²1 + cos²1 − 1`).
  var isZeroValue: Bool {
    if isZero { return true }
    guard freeSymbols.isEmpty else { return false }
    if let real = try? approximation(precision: 40) { return (real.decimalOrder ?? Int.min) < -35 }
    if let complex = try? complexApproximation(precision: 40) {
      return (complex.magnitudeSquared.decimalOrder ?? Int.min) < -70
    }
    return false
  }
}
