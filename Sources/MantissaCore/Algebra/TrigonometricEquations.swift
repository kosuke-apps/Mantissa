/// Equations in sines, cosines and tangents of one angle `ψ = a·x` and its whole multiples (`2 sin²x + sin x − 1 = 0`,
/// `sin 2x = sin x`, `sin x + cos x = 1`, `tan x = 1`): their solutions repeat, so they come as families `offset + period·n`.
///
/// Every trigonometric function of `mψ + q` is written in `S = sin ψ` and `C = cos ψ` (the real and imaginary parts of
/// `(C + iS)^m`, and the angle-addition formulas for `q`). The equation in `S` and `C` is then solved the simplest way that
/// applies: in `S` alone, in `C` alone, as `A sin ψ + B cos ψ = D` by the amplitude–phase form, and otherwise through
/// `tan(ψ/2)`, which turns any polynomial in `S` and `C` into one in a single unknown. Families are checked in the original.
enum TrigonometricEquations {
  static func solve(_ expression: Expr, _ variable: String) -> Solved? {
    let atoms = expression.collect(where: { part in
      guard case .function(let function, let arguments) = part, [.sin, .cos, .tan].contains(function) else {
        return false
      }
      return arguments[0].contains(variable)
    })
    guard !atoms.isEmpty else { return nil }

    // Each angle as slope·x + offset; the base angle ψ has the smallest slope, the others are whole multiples of it.
    struct Angle {
      var function: MathFunction
      var slope: Expr
      var offset: Expr
    }
    var angles: [Angle] = []
    for atom in atoms {
      guard case .function(let function, let arguments) = atom, let polynomial = arguments[0].polynomial(in: variable),
        polynomial.degree == 1
      else { return nil }
      angles.append(Angle(function: function, slope: polynomial.coefficients[1], offset: polynomial.coefficients[0]))
    }
    guard
      let base = angles.min(by: { (($0.slope.realValue ?? 0).magnitude) < (($1.slope.realValue ?? 0).magnitude) })?
        .slope,
      let baseValue = base.realValue, !baseValue.isZero
    else { return nil }
    var multiples: [Int] = []
    for angle in angles {
      guard let ratio = try? angle.slope.divided(by: base), let m = ratio.rational, m.isInteger,
        let whole = m.numerator.asInt,
        whole != 0, abs(whole) <= 8
      else { return nil }
      multiples.append(whole)
    }

    // The equation in S and C.
    let s = Expr.symbol("ts")
    let c = Expr.symbol("tc")
    guard !expression.contains("ts"), !expression.contains("tc") else { return nil }
    var cache: [Int: (cos: Expr, sin: Expr)] = [:]
    func multipleAngle(_ m: Int) -> (cos: Expr, sin: Expr)? {
      if let known = cache[m] { return known }
      guard let power = try? (c + .i * s).raised(to: .integer(m)), let (re, im) = power.expanded().complexParts() else {
        return nil
      }
      cache[m] = (re, im)
      return (re, im)
    }
    func sineAndCosine(of index: Int) -> (sin: Expr, cos: Expr)? {
      let m = multiples[index]
      guard let (cosM, sinM) = multipleAngle(abs(m)),
        let cosQ = try? Expr.apply(.cos, [angles[index].offset]),
        let sinQ = try? Expr.apply(.sin, [angles[index].offset])
      else { return nil }
      let sinMultiple = m < 0 ? -sinM : sinM
      return (sinMultiple * cosQ + cosM * sinQ, cosM * cosQ - sinMultiple * sinQ)
    }

    var failed = false
    let replaced = expression.replacing { part in
      guard let index = atoms.firstIndex(of: part) else { return nil }
      guard let (sin, cos) = sineAndCosine(of: index) else {
        failed = true
        return nil
      }
      switch angles[index].function {
      case .sin: return sin
      case .cos: return cos
      default: return sin * Expr.makePower(cos.expanded(), .minusOne)
      }
    }
    guard !failed, let replaced, !replaced.contains(variable) else { return nil }

    // Clear denominators (from tangents) and reduce to a polynomial in S and C.
    var denominators: [Expr: Int] = [:]
    for power in replaced.collectAll(where: {
      if case .power(_, let e) = $0, e.rational?.isInteger == true, e.rational!.signum < 0 {
        return true
      } else {
        return false
      }
    }) {
      if case .power(let b, let e) = power, let n = e.rational?.numerator.asInt {
        denominators[b] = max(denominators[b] ?? 0, -n)
      }
    }
    var cleared = replaced
    for (base, power) in denominators {
      guard let factor = try? base.raised(to: .integer(power)) else { return nil }
      cleared = cleared * factor
    }
    let equation = cleared.expanded()

    guard let angles = solveForAngle(equation, s: s, c: c) else { return nil }
    // x = ψ / a.
    var families: [PeriodicSolution] = []
    for angle in angles {
      let scale = Expr.makePower(base, .minusOne)
      families.append(
        PeriodicSolution(offset: (angle.offset * scale).expanded(), period: (angle.period * scale).expanded()))
    }
    families = merged(families.map(normalised))
    families = families.filter { family in
      (-2...2).allSatisfy { n in
        guard let value = SolvedValue.exact(family.offset + family.period * Expr.integer(n)) else { return false }
        return TranscendentalSolver.verifies(value, expression, variable)
      }
    }
    families.sort { ($0.offsetApproximation ?? 0) < ($1.offsetApproximation ?? 0) }
    return families.isEmpty ? .none(variable: variable) : .periodic(variable: variable, families)
  }

  // MARK: Solving for ψ

  /// A family `offset + period·n` of values of the angle ψ.
  private struct AngleFamily {
    var offset: Expr
    var period: Expr
  }

  private static let twoPi = Expr.integer(2) * .pi

  private static func solveForAngle(_ equation: Expr, s: Expr, c: Expr) -> [AngleFamily]? {
    guard case .symbol(let sName) = s, case .symbol(let cName) = c else { return nil }

    // Sine alone, then cosine alone, using sin² + cos² = 1.
    if let polynomial = reducedToOne(equation, keep: sName, eliminate: cName) {
      return sineFamilies(polynomial, sName)
    }
    if let polynomial = reducedToOne(equation, keep: cName, eliminate: sName) {
      return cosineFamilies(polynomial, cName)
    }
    // A sin ψ + B cos ψ + D = 0.
    if let families = linearCombination(equation, sName, cName) { return families }
    return halfAngleFamilies(equation, sName, cName)
  }

  /// The equation as a polynomial in `keep` alone, when `eliminate` appears only to even powers (and so is replaced using
  /// `keep² + eliminate² = 1`).
  private static func reducedToOne(_ equation: Expr, keep: String, eliminate: String) -> Polynomial? {
    guard let polynomial = equation.polynomial(in: eliminate) else { return nil }
    let one = Expr.symbol(keep)
    var total: [Expr] = []
    for (power, coefficient) in polynomial.coefficients.enumerated() {
      if power % 2 == 1 {
        if !coefficient.isZero { return nil }
        continue
      }
      guard let factor = try? (Expr.one - one * one).raised(to: .integer(power / 2)) else { return nil }
      total.append(coefficient * factor)
    }
    return Expr.makeSum(total).expanded().polynomial(in: keep)
  }

  private static func sineFamilies(_ polynomial: Polynomial, _ name: String) -> [AngleFamily]? {
    guard let roots = realRoots(of: polynomial) else { return nil }
    var families: [AngleFamily] = []
    for root in roots {
      guard let value = root.realValue, value.magnitude <= BigDecimal(1), let exact = root.exact,
        let arcsine = try? Expr.apply(.asin, [exact])
      else { continue }
      families.append(AngleFamily(offset: arcsine, period: twoPi))
      if value.magnitude != BigDecimal(1) { families.append(AngleFamily(offset: Expr.pi - arcsine, period: twoPi)) }
    }
    return families
  }

  private static func cosineFamilies(_ polynomial: Polynomial, _ name: String) -> [AngleFamily]? {
    guard let roots = realRoots(of: polynomial) else { return nil }
    var families: [AngleFamily] = []
    for root in roots {
      guard let value = root.realValue, value.magnitude <= BigDecimal(1), let exact = root.exact,
        let arccosine = try? Expr.apply(.acos, [exact])
      else { continue }
      families.append(AngleFamily(offset: arccosine, period: twoPi))
      if value.magnitude != BigDecimal(1) { families.append(AngleFamily(offset: -arccosine, period: twoPi)) }
    }
    return families
  }

  private static func realRoots(of polynomial: Polynomial) -> [SolvedValue]? {
    if polynomial.degree < 1 { return [] }
    guard let roots = EquationSolver.roots(of: polynomial) else { return nil }
    return roots.filter(\.isReal)
  }

  /// `A sin ψ + B cos ψ + D = 0` with `A` and `B` both nonzero numbers (if one is zero the equation is in S alone or C alone,
  /// which is handled before): with `φ = arctan(B/A)` it is `sign(A)·R·sin(ψ + φ) = −D` for `R = √(A² + B²)`.
  private static func linearCombination(_ equation: Expr, _ sName: String, _ cName: String) -> [AngleFamily]? {
    guard let inS = equation.polynomial(in: sName), inS.degree == 1,
      let inC = inS.coefficients[0].polynomial(in: cName),
      inC.degree <= 1
    else { return nil }
    let a = inS.coefficients[1]
    let b = inC.degree == 1 ? inC.coefficients[1] : Expr.zero
    let d = inC.coefficients.first ?? Expr.zero
    guard a.freeSymbols.isEmpty, b.freeSymbols.isEmpty, d.freeSymbols.isEmpty, !b.isZero, let aValue = a.realValue
    else {
      return nil
    }

    let radius = Expr.makePower((a * a + b * b).expanded(), .fraction(1, 2))
    guard let ratio = try? b.divided(by: a), let phase = try? Expr.apply(.atan, [ratio]) else { return nil }
    let sign: Expr = aValue.isNegative ? .minusOne : .one
    guard let target = try? (-d).divided(by: radius * sign), let value = target.realValue else { return nil }
    guard value.magnitude <= BigDecimal(1), let arcsine = try? Expr.apply(.asin, [target]) else { return [] }
    var families = [AngleFamily(offset: arcsine - phase, period: twoPi)]
    if value.magnitude != BigDecimal(1) {
      families.append(AngleFamily(offset: Expr.pi - arcsine - phase, period: twoPi))
    }
    return families
  }

  /// Any polynomial in S and C, through τ = tan(ψ/2): S = 2τ/(1 + τ²), C = (1 − τ²)/(1 + τ²), and ψ = π is τ = ∞.
  private static func halfAngleFamilies(_ equation: Expr, _ sName: String, _ cName: String) -> [AngleFamily]? {
    let tau = Expr.symbol("tau")
    let denominator = Expr.one + tau * tau
    guard let sines = try? (Expr.integer(2) * tau).divided(by: denominator),
      let cosines = try? (Expr.one - tau * tau).divided(by: denominator),
      let substituted = equation.substituting(sName, with: sines)?.substituting(cName, with: cosines),
      let (numerator, _) = substituted.together(variable: "tau"), let polynomial = numerator.polynomial(in: "tau")
    else { return nil }

    var families: [AngleFamily] = []
    if polynomial.degree >= 1 {
      guard let roots = EquationSolver.roots(of: polynomial) else { return nil }
      for root in roots where root.isReal {
        guard let exact = root.exact, let arctangent = try? Expr.apply(.atan, [exact]) else { continue }
        families.append(AngleFamily(offset: Expr.integer(2) * arctangent, period: twoPi))
      }
    }
    // ψ = π, where tan(ψ/2) is not defined.
    if let atPi = equation.substituting(sName, with: .zero)?.substituting(cName, with: .minusOne), atPi.isZeroValue {
      families.append(AngleFamily(offset: .pi, period: twoPi))
    }
    return families
  }

  // MARK: Merging

  /// The same family with its offset brought into [0, period): `−π/6 + 2πn` is `11π/6 + 2πn`.
  private static func normalised(_ family: PeriodicSolution) -> PeriodicSolution {
    guard let offset = family.offsetApproximation, let period = family.periodApproximation, period.signum > 0,
      let quotient = try? offset.divided(by: period, precision: 40)
    else { return family }
    let turns = quotient.floor
    if turns.isZero { return family }
    guard let shift = turns.asInt else { return family }
    return PeriodicSolution(
      offset: (family.offset - Expr.integer(shift) * family.period).expanded(), period: family.period)
  }

  /// Families that differ by half a period are one family of half the period: `{0 + 2πn, π + 2πn}` is `πn`. Repeated until
  /// nothing more merges, so `{π/4, 3π/4, 5π/4, 7π/4} + 2πn` becomes `π/4 + (π/2)n`.
  private static func merged(_ families: [PeriodicSolution]) -> [PeriodicSolution] {
    var current = families
    while true {
      var remaining = current
      var result: [PeriodicSolution] = []
      var changed = false
      while let first = remaining.first {
        remaining.removeFirst()
        let half = (first.period * Expr.fraction(1, 2)).expanded()
        guard
          let index = remaining.firstIndex(where: { other in
            other.period == first.period
              && ((other.offset - first.offset - half).expanded().isZeroValue
                || (first.offset - other.offset - half).expanded().isZeroValue)
          })
        else {
          result.append(first)
          continue
        }
        let other = remaining.remove(at: index)
        let lower = (other.offset.realValue ?? 0) < (first.offset.realValue ?? 0) ? other.offset : first.offset
        result.append(normalised(PeriodicSolution(offset: lower, period: half)))
        changed = true
      }
      current = result
      if !changed { return current }
    }
  }
}
