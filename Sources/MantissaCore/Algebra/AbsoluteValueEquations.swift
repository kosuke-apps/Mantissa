/// Equations with absolute values: the line is cut where an argument changes sign, and on each stretch the absolute values
/// are replaced by plus or minus their arguments, which leaves an equation without them.
enum AbsoluteValueEquations {
  private static func isAbsolute(_ expression: Expr) -> Bool {
    if case .function(.abs, _) = expression { return true }
    return false
  }

  static func solve(_ expression: Expr, _ variable: String) -> [SolvedValue]? {
    // Only an absolute value with the unknown inside it is cut: one of a constant is no business of this strategy, and going on
    // would hand the same expression back to the transcendental solver, which hands it back here.
    let hasUnknownInside = !expression.collectAll(where: { part in
      guard case .function(.abs, let arguments) = part else { return false }
      return arguments[0].contains(variable)
    }).isEmpty
    guard hasUnknownInside else { return nil }
    return solve(expression, variable, from: nil, to: nil)
  }

  /// The solutions between `lower` and `upper` (either may be unbounded).
  private static func solve(
    _ expression: Expr, _ variable: String, from lower: BigDecimal?, to upper: BigDecimal?
  )
    -> [SolvedValue]?
  {
    // The absolute values with none inside them go first: ||x| − 1| is cut by |x| − 1 only after |x| is resolved.
    let innermost = expression.collectAll(where: { part in
      guard case .function(.abs, let arguments) = part else { return false }
      return arguments[0].contains(variable) && arguments[0].collectAll(where: isAbsolute).isEmpty
    })
    guard !innermost.isEmpty else {
      let roots = TranscendentalSolver.realSolutions(of: expression, variable)
      return roots?.filter { inside($0, lower, upper) }
    }

    // Where each argument is zero.
    var breakpoints: [SolvedValue] = []
    for atom in innermost {
      guard case .function(_, let arguments) = atom,
        let (numerator, denominators) = arguments[0].together(variable: variable),
        let polynomial = numerator.polynomial(in: variable)
      else { return nil }
      var polynomials = [polynomial]
      for denominator in denominators {
        guard let base = denominator.base.polynomial(in: variable) else { return nil }
        polynomials.append(base)
      }
      for p in polynomials where p.degree >= 1 {
        guard let roots = EquationSolver.roots(of: p) else { return nil }
        breakpoints += roots.filter(\.isReal)
      }
    }
    breakpoints = EquationSolver.sortedAndDistinct(breakpoints)
    let points = breakpoints.compactMap(\.realValue)

    var candidates: [SolvedValue] = []
    for stretch in 0...points.count {
      let low = stretch == 0 ? nil : points[stretch - 1]
      let high = stretch == points.count ? nil : points[stretch]
      // Only the part of this stretch that is inside the range being solved.
      let from = [low, lower].compactMap { $0 }.max()
      let to = [high, upper].compactMap { $0 }.min()
      if let from, let to, from > to { continue }

      let test = testPoint(low, high)
      // An argument with no value at the test point (it holds something undefined) cannot be resolved; leaving its bars in
      // would send the same expression round again, so the stretch is skipped.
      var unresolved = false
      let resolved = expression.replacing { part in
        guard innermost.contains(part), case .function(_, let arguments) = part else { return nil }
        guard let value = try? arguments[0].approximation(precision: 40, values: [variable: test]) else {
          unresolved = true
          return nil
        }
        return value.isNegative ? -arguments[0] : arguments[0]
      }
      guard !unresolved, let resolved, resolved != expression else { continue }
      guard let found = solve(resolved, variable, from: from, to: to) else { return nil }
      candidates += found
    }
    return candidates
  }

  private static func inside(_ value: SolvedValue, _ lower: BigDecimal?, _ upper: BigDecimal?) -> Bool {
    guard let real = value.realValue else { return false }
    let slack = BigDecimal(BigInt(1), exponent: -35) * max(BigDecimal(1), real.magnitude)
    if let lower, real < lower - slack { return false }
    if let upper, real > upper + slack { return false }
    return true
  }

  private static func testPoint(_ low: BigDecimal?, _ high: BigDecimal?) -> BigDecimal {
    switch (low, high) {
    case (nil, nil): return BigDecimal(0)
    case (let low?, nil): return low + BigDecimal(1)
    case (nil, let high?): return high - BigDecimal(1)
    case (let low?, let high?): return (try? (low + high).divided(by: BigDecimal(2), precision: 50)) ?? low
    }
  }
}
