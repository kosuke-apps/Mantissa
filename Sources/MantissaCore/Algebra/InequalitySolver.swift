/// Solves inequalities in one unknown whose two sides are polynomials or fractions of polynomials.
///
/// Everything an inequality can change at is a real root of a numerator (where the value is zero) or of a denominator
/// (where it is not defined). Those points cut the real line into stretches on each of which the sign is fixed, so the sign
/// is read at one point of each stretch, and the stretches and points that satisfy every condition are joined up.
enum InequalitySolver {
  /// `expression op 0`.
  struct Constraint {
    var expression: Expr
    var op: RelationOperator
  }

  private struct Analysis {
    var numeratorRoots: [SolvedValue]
    var denominatorRoots: [SolvedValue]
  }

  static func solve(_ constraints: [Constraint], variable: String) -> Solved? {
    var analyses: [Analysis] = []
    var critical: [SolvedValue] = []
    for constraint in constraints {
      guard constraint.expression.freeSymbols.isSubset(of: [variable]),
        let (numerator, denominators) = constraint.expression.together(variable: variable),
        let polynomial = numerator.polynomial(in: variable)
      else { return nil }
      var numeratorRoots: [SolvedValue] = []
      if polynomial.degree >= 1 {
        guard let roots = EquationSolver.roots(of: polynomial) else { return nil }
        numeratorRoots = roots.filter(\.isReal)
      }
      var denominatorRoots: [SolvedValue] = []
      for denominator in denominators {
        guard let base = denominator.base.polynomial(in: variable), base.degree >= 1,
          let roots = EquationSolver.roots(of: base)
        else { return nil }
        denominatorRoots += roots.filter(\.isReal)
      }
      analyses.append(Analysis(numeratorRoots: numeratorRoots, denominatorRoots: denominatorRoots))
      critical += numeratorRoots + denominatorRoots
    }
    critical = EquationSolver.sortedAndDistinct(critical)

    // The elements of the line in order: the stretch before the first point, the first point, the stretch after it, ...
    let points = critical.map { $0.approximation!.real }
    var satisfied: [Bool] = []
    for element in 0...(2 * points.count) {
      if element % 2 == 1 {
        let point = critical[element / 2]
        satisfied.append(
          constraints.indices.allSatisfy { holds(at: point, constraints[$0], analyses[$0], variable: variable) })
      } else {
        let test = testPoint(stretch: element / 2, points: points)
        satisfied.append(constraints.allSatisfy { holdsBetween(at: test, $0, variable: variable) })
      }
    }

    // Runs of consecutive satisfied elements are the intervals.
    var intervals: [SolvedInterval] = []
    var start = 0
    while start < satisfied.count {
      guard satisfied[start] else {
        start += 1
        continue
      }
      var end = start
      while end + 1 < satisfied.count, satisfied[end + 1] { end += 1 }
      // Element 2k is the stretch before critical point k and element 2k + 1 is point k itself, so an end that is a stretch
      // is bounded (open) by the point beside it, and an end that is a point (closed) is that point.
      let lower: SolvedBound? =
        start == 0
        ? nil : SolvedBound(value: critical[start % 2 == 1 ? start / 2 : start / 2 - 1], isClosed: start % 2 == 1)
      let upper: SolvedBound? =
        end == satisfied.count - 1 ? nil : SolvedBound(value: critical[end / 2], isClosed: end % 2 == 1)
      intervals.append(SolvedInterval(lower: lower, upper: upper))
      start = end + 1
    }

    if intervals.isEmpty { return .none(variable: variable) }
    if intervals.count == 1, intervals[0].lower == nil, intervals[0].upper == nil {
      return .everything(variable: variable, excluding: [])
    }
    return .intervals(variable: variable, intervals)
  }

  // MARK: Signs

  /// Whether the relation holds at a critical point, which is where some numerator or denominator is zero.
  private static func holds(
    at point: SolvedValue, _ constraint: Constraint, _ analysis: Analysis, variable: String
  )
    -> Bool
  {
    if analysis.denominatorRoots.contains(where: { same($0, point) }) { return false }
    if analysis.numeratorRoots.contains(where: { same($0, point) }) { return satisfies(constraint.op, sign: 0) }
    // A point that matters to another condition only: read the sign there.
    guard let real = point.approximation?.real, let sign = sign(of: constraint.expression, at: real, variable: variable)
    else { return false }
    return satisfies(constraint.op, sign: sign)
  }

  private static func holdsBetween(at test: BigDecimal, _ constraint: Constraint, variable: String) -> Bool {
    guard let sign = sign(of: constraint.expression, at: test, variable: variable) else { return false }
    return satisfies(constraint.op, sign: sign)
  }

  private static func sign(of expression: Expr, at value: BigDecimal, variable: String) -> Int? {
    guard let result = try? expression.approximation(precision: 50, values: [variable: value]) else { return nil }
    if result.isZero { return 0 }
    if let order = result.decimalOrder, order < -30 { return 0 }
    return result.isNegative ? -1 : 1
  }

  static func satisfies(_ op: RelationOperator, sign: Int) -> Bool {
    switch op {
    case .less: return sign < 0
    case .lessOrEqual: return sign <= 0
    case .greater: return sign > 0
    case .greaterOrEqual: return sign >= 0
    case .equal: return sign == 0
    case .notEqual: return sign != 0
    }
  }

  private static func same(_ a: SolvedValue, _ b: SolvedValue) -> Bool {
    guard let x = a.approximation?.real, let y = b.approximation?.real else { return false }
    let scale = max(BigDecimal(1), x.magnitude)
    return (x - y).magnitude <= scale * BigDecimal(BigInt(1), exponent: -30)
  }

  /// A point inside the stretch before the first critical point (stretch 0), between two of them, or after the last.
  private static func testPoint(stretch: Int, points: [BigDecimal]) -> BigDecimal {
    if points.isEmpty { return BigDecimal(0) }
    if stretch == 0 { return points[0] - BigDecimal(1) }
    if stretch == points.count { return points[stretch - 1] + BigDecimal(1) }
    let sum = points[stretch - 1] + points[stretch]
    return (try? sum.divided(by: BigDecimal(2), precision: 50)) ?? points[stretch - 1]
  }
}
