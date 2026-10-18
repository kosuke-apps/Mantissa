// Inequalities with trigonometric functions, such as `sin x > 1/2` or `tan x > 1`: the solution repeats, so it is a set of
// intervals `lower + period·n < x < upper + period·n`.

enum PeriodicInequalities {
  /// A point where the sign of the expression can change: a root (the expression is zero there) or a pole (it is not
  /// defined there, so the point never belongs to the solution).
  private struct Point {
    var expression: Expr
    var value: BigDecimal
    var isRoot: Bool
  }

  private static let tolerance = BigDecimal(BigInt(1), exponent: -20)

  /// Solves `constraint` for `variable`, or `nil` when the roots and poles of the expression are not periodic solutions of a
  /// kind the trigonometric solver knows.
  ///
  /// The roots (from the numerator) and the poles (from the denominators) are the only places the sign can change. They are
  /// listed over two periods, since the expression may take twice as long to repeat as its roots do (`cos 2x` has a root every
  /// π/2 and a period of π). The sign between two neighbours is read from the expression at the middle, and the stretches that
  /// satisfy the inequality are joined across a root when the root belongs to the solution (≤ and ≥).
  static func solve(_ constraint: InequalitySolver.Constraint, _ variable: String) -> Solved? {
    guard constraint.expression.freeSymbols == [variable], constraint.op != .equal, constraint.op != .notEqual else {
      return nil
    }
    let original = constraint.expression
    let expression = withTangentsAsQuotients(original)
    guard let (numerator, denominators) = expression.together(variable: variable) else { return nil }

    // Every family of roots and poles, with its period.
    var families: [(family: PeriodicSolution, isRoot: Bool)] = []
    if numerator.contains(variable) {
      guard let solved = TrigonometricEquations.solve(numerator, variable) else { return nil }
      switch solved {
      case .periodic(_, let found): families += found.map { ($0, true) }
      case .none: break
      default: return nil
      }
    }
    for denominator in denominators {
      guard let solved = TrigonometricEquations.solve(denominator.base, variable) else { return nil }
      switch solved {
      case .periodic(_, let found): families += found.map { ($0, false) }
      case .none: break
      default: return nil
      }
    }

    // No point at which the sign can change: it is the same everywhere.
    if families.isEmpty {
      var signs = Set<Int>()
      for sample in ["0.37", "1.1", "2.9", "-0.8"] {
        guard let x = BigDecimal(sample), let value = try? original.approximation(precision: 40, values: [variable: x])
        else { continue }
        signs.insert(value.isNegative ? -1 : 1)
      }
      guard signs.count == 1, let sign = signs.first else { return nil }
      return InequalitySolver.satisfies(constraint.op, sign: sign)
        ? .everything(variable: variable, excluding: []) : .none(variable: variable)
    }

    // One period for all: the longest, when the others divide it.
    guard let longest = families.compactMap({ $0.family.periodApproximation }).max(), longest.signum > 0,
      let basis = families.first(where: { $0.family.periodApproximation == longest })?.family.period
    else { return nil }
    var points: [Point] = []
    for (family, isRoot) in families {
      guard let length = family.periodApproximation, let start = family.offsetApproximation,
        let ratio = (try? longest.divided(by: length, precision: 30)), let copies = Self.wholeNumber(ratio),
        copies >= 1, copies <= 12
      else { return nil }
      for copy in 0..<copies {
        let shift = Expr.makeProduct([.integer(copy), family.period])
        let value = start + BigDecimal(BigInt(copy)) * length
        points.append(Point(expression: Expr.makeSum([family.offset, shift]), value: value, isRoot: isRoot))
      }
    }
    // Over two periods.
    let single = points
    for point in single {
      points.append(
        Point(
          expression: Expr.makeSum([point.expression, basis]), value: point.value + longest, isRoot: point.isRoot))
    }
    points.sort { $0.value < $1.value }
    var distinct: [Point] = []
    for point in points {
      if let last = distinct.last, (point.value - last.value).magnitude < tolerance {
        // A root that is also a pole is a pole.
        if !point.isRoot { distinct[distinct.count - 1].isRoot = false }
      } else {
        distinct.append(point)
      }
    }
    points = distinct
    let count = points.count
    guard count >= 2 else { return nil }
    let whole = longest * BigDecimal(2)

    // The sign in each stretch, from point i to the next (the last wraps round to the first, a whole cycle later).
    var satisfied: [Bool] = []
    for index in 0..<count {
      let start = points[index].value
      let end = index + 1 < count ? points[index + 1].value : points[0].value + whole
      let middle = (start + end) * BigDecimal(BigInt(5), exponent: -1)
      guard let value = try? original.approximation(precision: 40, values: [variable: middle]),
        (value.decimalOrder ?? Int.min) >= -25
      else { return nil }
      satisfied.append(InequalitySolver.satisfies(constraint.op, sign: value.isNegative ? -1 : 1))
    }
    let includesPoints = constraint.op == .lessOrEqual || constraint.op == .greaterOrEqual
    let period = Expr.makeProduct([.integer(2), basis])

    if !satisfied.contains(true) {
      guard includesPoints else { return Solved.none(variable: variable) }
      // Only the roots themselves.
      let roots = points.filter(\.isRoot)
      guard !roots.isEmpty else { return Solved.none(variable: variable) }
      return reduced(roots.map { ($0.expression, $0.value) }, period: basis, length: whole, variable: variable)
    }
    if !satisfied.contains(false) && includesPoints && points.allSatisfy(\.isRoot) {
      return .everything(variable: variable, excluding: [])
    }

    // Runs of satisfied stretches, joined across a root that belongs to the solution.
    func joins(_ index: Int) -> Bool { includesPoints && points[index % count].isRoot }
    var intervals: [(low: Point, high: Point, highValue: BigDecimal)] = []
    var visited = [Bool](repeating: false, count: count)
    var begin = 0
    if let first = (0..<count).first(where: { satisfied[$0] && !(satisfied[($0 + count - 1) % count] && joins($0)) }) {
      begin = first
    } else {
      return nil  // every stretch is joined to the next all the way round: the whole line
    }
    for step in 0..<count {
      let index = (begin + step) % count
      guard satisfied[index], !visited[index] else { continue }
      visited[index] = true
      var last = index
      while satisfied[(last + 1) % count], joins(last + 1), !visited[(last + 1) % count] {
        last = (last + 1) % count
        visited[last] = true
      }
      // The end of the run is the point after its last stretch, a cycle later if it has wrapped round.
      let next = (last + 1) % count
      var high = points[next]
      var highValue = high.value
      if next <= index {
        highValue += whole
        high.expression = Expr.makeSum([high.expression, period])
      }
      intervals.append((points[index], high, highValue))
    }
    intervals.sort { $0.low.value < $1.low.value }

    // Do the intervals repeat after half the cycle? Then the cycle is the period of the roots, not twice it.
    let half = longest
    var reducible = true
    for interval in intervals {
      let twin = interval.low.value + half
      let shifted = twin >= whole ? twin - whole : twin
      let found = intervals.contains {
        ($0.low.value - shifted).magnitude < tolerance
          && (($0.highValue - $0.low.value) - (interval.highValue - interval.low.value)).magnitude < tolerance
      }
      if !found { reducible = false }
    }
    var kept = intervals
    var finalPeriod = period
    if reducible {
      kept = intervals.filter { $0.low.value < half }
      finalPeriod = basis
    }
    let result = kept.map { interval in
      SolvedInterval(
        lower: SolvedBound(
          value: SolvedValue(exact: interval.low.expression, approximation: ComplexDecimal(real: interval.low.value)),
          isClosed: includesPoints && interval.low.isRoot),
        upper: SolvedBound(
          value: SolvedValue(exact: interval.high.expression, approximation: ComplexDecimal(real: interval.highValue)),
          isClosed: includesPoints && interval.high.isRoot))
    }
    return .periodicIntervals(
      variable: variable, result, period: PeriodicSolution(offset: .zero, period: finalPeriod))
  }

  /// The roots alone as periodic families, with a period that is not repeated within it.
  private static func reduced(
    _ roots: [(Expr, BigDecimal)], period: Expr, length: BigDecimal, variable: String
  ) -> Solved? {
    let families = roots.filter { $0.1 < length * BigDecimal(BigInt(5), exponent: -1) }
    return .periodic(variable: variable, families.map { PeriodicSolution(offset: $0.0, period: period) })
  }

  private static func wholeNumber(_ value: BigDecimal) -> Int? {
    let rounded = value.rounded(toPlaces: 0)
    guard (value - rounded).magnitude < BigDecimal(BigInt(1), exponent: -15), let whole = rounded.asInt else {
      return nil
    }
    return whole
  }

  /// The expression with each `tan u` written as `sin u / cos u`, so that its poles show up as a denominator.
  private static func withTangentsAsQuotients(_ expression: Expr) -> Expr {
    switch expression {
    case .number, .constant, .symbol: return expression
    case .sum(let terms): return Expr.makeSum(terms.map(withTangentsAsQuotients))
    case .product(let factors): return Expr.makeProduct(factors.map(withTangentsAsQuotients))
    case .power(let base, let exponent):
      return Expr.makePower(withTangentsAsQuotients(base), withTangentsAsQuotients(exponent))
    case .function(.tan, let arguments):
      let angle = withTangentsAsQuotients(arguments[0])
      guard let sine = try? Expr.apply(.sin, [angle]), let cosine = try? Expr.apply(.cos, [angle]) else {
        return expression
      }
      return Expr.makeProduct([sine, Expr.makePower(cosine, .minusOne)])
    case .function(let function, let arguments):
      return (try? Expr.apply(function, arguments.map(withTangentsAsQuotients))) ?? expression
    }
  }
}
