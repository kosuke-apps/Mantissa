/// Real solutions of an equation that has no closed form (`e^x = x + 2`, `x = cos x`, `2^x = x²`), as decimals.
///
/// The function is sampled between −100 and 100, a sign change or a touching of zero is spotted and located in `Double`
/// (the same machinery that marks the roots of a graph), and each root is refined by Newton's method in 60 digits. A root
/// that is a simple fraction is given as that fraction. Nothing is claimed about solutions outside the window, so an
/// equation with none inside is not reported as having none, and one with very many (a periodic one this solver did not
/// recognise) is not solved.
enum NumericEquations {
  static let window = 100.0
  private static let maxRoots = 30

  static func solve(_ expression: Expr, _ variable: String) -> [SolvedValue]? {
    let rename = variable == "x" ? expression : expression.substituting(variable, with: .symbol("x"))
    guard let plotted = rename, plotted.freeSymbols == ["x"] else { return nil }
    let function = PlotFunction(plotted)
    let found = PlotAnalysis.points(of: [function], from: -window, to: window, samples: 8000).filter {
      $0.kind == .root
    }
    guard !found.isEmpty, found.count <= maxRoots else { return nil }

    var values: [SolvedValue] = []
    for point in found {
      guard let start = BigDecimal("\(point.x)"), let refined = refine(expression, variable, start: start) else {
        continue
      }
      let value =
        simpleFraction(refined, expression, variable)
        ?? SolvedValue(exact: nil, approximation: ComplexDecimal(real: refined))
      if TranscendentalSolver.verifies(value, expression, variable) { values.append(value) }
    }
    return values.isEmpty ? nil : EquationSolver.sortedAndDistinct(values)
  }

  /// Newton's method with a numerical derivative.
  private static func refine(_ expression: Expr, _ variable: String, start: BigDecimal) -> BigDecimal? {
    // A value of astronomical size (e^3628800·x) is no use to Newton's method, and subtracting two of them exactly would build an
    // integer with millions of digits, so such a value is given up on.
    func value(_ x: BigDecimal) -> BigDecimal? {
      guard let result = try? expression.approximation(precision: 60, values: [variable: x]) else { return nil }
      if let order = result.decimalOrder, abs(order) > 1000 { return nil }
      return result
    }
    var x = start
    for _ in 0..<10 {
      guard let f = value(x) else { return nil }
      if f.isZero { return x }
      let step = BigDecimal(BigInt(1), exponent: -25) * max(BigDecimal(1), x.magnitude)
      guard let f1 = value(x.adding(step, precision: 70)),
        let slope = try? f1.adding(-f, precision: 70).divided(by: step, precision: 60), !slope.isZero,
        let change = try? f.divided(by: slope, precision: 60)
      else { return x }
      let next = x.adding(-change, precision: 70)
      if next.adding(-x, precision: 70).magnitude < BigDecimal(BigInt(1), exponent: -45)
        * max(BigDecimal(1), x.magnitude)
      {
        return next.rounded(toSignificantDigits: 50)
      }
      x = next
    }
    return x.rounded(toSignificantDigits: 50)
  }

  /// The root as an exact fraction when it is one with a small denominator (2 and 4 for `2^x = x²`).
  private static func simpleFraction(_ root: BigDecimal, _ expression: Expr, _ variable: String) -> SolvedValue? {
    for denominator in 1...24 {
      let scaled = root * BigDecimal(denominator)
      let nearest = scaled.rounded(toPlaces: 0)
      guard (scaled - nearest).magnitude < BigDecimal(BigInt(1), exponent: -25) else { continue }
      let exact = Expr.number(Rational(nearest.floor, BigInt(denominator)))
      let candidate = SolvedValue(
        exact: exact,
        approximation: ComplexDecimal(real: BigDecimal(Rational(nearest.floor, BigInt(denominator)), precision: 50)))
      if TranscendentalSolver.verifies(candidate, expression, variable) { return candidate }
    }
    return nil
  }
}
