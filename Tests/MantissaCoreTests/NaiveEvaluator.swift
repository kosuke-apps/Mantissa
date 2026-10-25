@testable import MantissaCore

/// Evaluates parsed syntax straight to a decimal, with no simplification at all: no radical rules, no collecting of
/// terms, no exact trigonometric tables. It is slow and blunt on purpose. Whatever the canonical `Expr` machinery does
/// to an expression, its value must agree with this one, so any simplification rule that changes a value is caught.
struct NaiveEvaluator {
  var angleUnit: AngleUnit
  let precision = 120

  func evaluate(_ syntax: Syntax) throws(MathError) -> BigDecimal {
    let p = precision
    switch syntax {
    case .number(let value): return BigDecimal(value, precision: p)
    case .symbol, .infinity, .matrix: throw .notNumeric
    case .constant(let constant):
      switch constant {
      case .pi: return BigDecimal.pi(precision: p)
      case .e: return BigDecimal.e(precision: p)
      default: throw .domain
      }
    case .negate(let operand): return -(try evaluate(operand))
    case .binary(let op, let left, let right):
      let a = try evaluate(left)
      let b = try evaluate(right)
      switch op {
      case .add: return a.adding(b, precision: p)
      case .subtract: return a.adding(-b, precision: p)
      case .multiply: return (a * b).rounded(toSignificantDigits: p)
      case .divide: return try a.divided(by: b, precision: p)
      case .power: return try power(a, b)
      }
    case .postfix(let op, let operand):
      let value = try evaluate(operand)
      switch op {
      case .factorial:
        guard let n = value.asInt, n >= 0 else { throw .domain }
        guard let result = NumberTheory.factorial(n) else { throw .overflow }
        return BigDecimal(result)
      case .percent: return try value.divided(by: BigDecimal(100), precision: p)
      case .degree: return angleUnit == .degrees ? value : try toRadians(value)
      }
    case .call(let function, let arguments):
      var values: [BigDecimal] = []
      for argument in arguments { values.append(try evaluate(argument)) }
      let mentionsPi = arguments.contains { $0.mentionsPi }
      return try call(function, values, mentionsPi: mentionsPi)
    case .radical(let index, let radicand):
      let value = try evaluate(radicand)
      guard let index else { return try value.squareRoot(precision: p) }
      return try root(value, index: try evaluate(index))
    }
  }

  private func power(_ base: BigDecimal, _ exponent: BigDecimal) throws(MathError) -> BigDecimal {
    if !exponent.isInteger { try requireWellConditioned(exponent) }
    return try base.power(exponent, precision: precision)
  }

  /// The naive evaluator carries `precision` digits and does not add any for a magnified error, so sin(10^98) or
  /// e^(10^98) is only good to about 20 digits here: too few to judge the exact layer by. Such cases are skipped
  /// (reported as `overflow`); the exact layer's handling of them is tested against Python in `ExprTests`.
  private func requireWellConditioned(_ argument: BigDecimal) throws(MathError) {
    if let order = argument.decimalOrder, order > 60 { throw .overflow }
  }

  /// An odd root of a negative number is real, as in the canonical form: ∛(−8) = −2.
  private func root(_ value: BigDecimal, index: BigDecimal) throws(MathError) -> BigDecimal {
    let reciprocal = try BigDecimal(1).divided(by: index, precision: precision)
    if value.isNegative, let n = index.asInt, n % 2 != 0 {
      return -(try value.magnitude.power(reciprocal, precision: precision))
    }
    return try value.power(reciprocal, precision: precision)
  }

  private func snapped(_ value: BigDecimal) -> BigDecimal {
    guard let order = value.decimalOrder, order < -(precision - 15) else { return value }
    return BigDecimal(0)
  }

  private func toRadians(_ value: BigDecimal) throws(MathError) -> BigDecimal {
    try (value * BigDecimal.pi(precision: precision)).divided(by: BigDecimal(180), precision: precision)
  }

  private func toDegrees(_ value: BigDecimal) throws(MathError) -> BigDecimal {
    try (value * BigDecimal(180)).divided(by: BigDecimal.pi(precision: precision), precision: precision)
  }

  private func call(_ function: FunctionName, _ x: [BigDecimal], mentionsPi: Bool) throws(MathError) -> BigDecimal {
    let p = precision
    switch function {
    case .sin, .cos, .tan:
      let angle = angleUnit == .degrees && !mentionsPi ? try toRadians(x[0]) : x[0]
      try requireWellConditioned(angle)
      // π is rounded here, so sin(π) comes out as about 1e-120 where the exact answer is 0; a value that small is that
      // residue and is counted as the zero it stands for.
      let sine = snapped(try angle.sin(precision: p))
      let cosine = snapped(try angle.cos(precision: p))
      switch function {
      case .sin: return sine
      case .cos: return cosine
      default: return try sine.divided(by: cosine, precision: p)
      }
    case .cot, .sec, .csc:
      let angle = angleUnit == .degrees && !mentionsPi ? try toRadians(x[0]) : x[0]
      try requireWellConditioned(angle)
      let sine = snapped(try angle.sin(precision: p))
      let cosine = snapped(try angle.cos(precision: p))
      switch function {
      case .cot: return try cosine.divided(by: sine, precision: p)
      case .sec: return try BigDecimal(1).divided(by: cosine, precision: p)
      default: return try BigDecimal(1).divided(by: sine, precision: p)
      }
    case .asin, .acos, .atan:
      let result: BigDecimal
      if function == .atan && x.count == 2 {
        // The angle of the point (x, y): the arctangent of the slope, moved into the right half-plane.
        let (y, abscissa) = (x[0], x[1])
        if abscissa.isZero {
          if y.isZero { throw .domain }
          let quarter = try BigDecimal.pi(precision: p).divided(by: BigDecimal(2), precision: p)
          return angleUnit == .degrees
            ? try toDegrees(y.isNegative ? -quarter : quarter) : (y.isNegative ? -quarter : quarter)
        }
        let base = try y.divided(by: abscissa, precision: p).arctangent(precision: p)
        let moved =
          abscissa.isNegative
          ? (y.isNegative ? base - BigDecimal.pi(precision: p) : base + BigDecimal.pi(precision: p)) : base
        return angleUnit == .degrees ? try toDegrees(moved) : moved
      }
      switch function {
      case .asin: result = try x[0].arcsine(precision: p)
      case .acos: result = try x[0].arccosine(precision: p)
      default: result = x[0].arctangent(precision: p)
      }
      return angleUnit == .degrees ? try toDegrees(result) : result
    case .sinh:
      try requireWellConditioned(x[0])
      return try x[0].sinh(precision: p)
    case .cosh:
      try requireWellConditioned(x[0])
      return try x[0].cosh(precision: p)
    case .tanh:
      try requireWellConditioned(x[0])
      return try x[0].tanh(precision: p)
    case .asinh: return try x[0].asinh(precision: p)
    case .acosh: return try x[0].acosh(precision: p)
    case .atanh: return try x[0].atanh(precision: p)
    case .ln: return try x[0].ln(precision: p)
    case .log: return try x[0].log(base: x.count == 2 ? x[1] : BigDecimal(10), precision: p)
    case .sqrt: return try x[0].squareRoot(precision: p)
    case .cbrt: return try root(x[0], index: BigDecimal(3))
    case .root: return try root(x[0], index: x[1])
    case .exp:
      try requireWellConditioned(x[0])
      return try x[0].exp(precision: p)
    case .abs: return x[0].magnitude
    case .floor: return BigDecimal(x[0].floor)
    case .ceil: return -BigDecimal((-x[0]).floor)
    case .round: return x[0].rounded(toPlaces: 0)
    case .diff, .int, .lim, .sum, .det, .inverse, .transpose, .trace, .rank, .rref, .dot, .cross, .norm, .identity,
      .eigvals, .eigvecs:
      throw .notNumeric
    case .nCr, .nPr:
      guard let n = x[0].asInt, let r = x[1].asInt, n >= 0, r >= 0, r <= n else { throw .domain }
      let value = function == .nCr ? NumberTheory.combinations(n, r) : NumberTheory.permutations(n, r)
      guard let result = value else { throw .overflow }
      return BigDecimal(result)
    case .acot:
      let result =
        try BigDecimal.pi(precision: p).divided(by: BigDecimal(2), precision: p) - x[0].arctangent(precision: p)
      return angleUnit == .degrees ? try toDegrees(result) : result
    case .asec, .acsc:
      let reciprocal = try BigDecimal(1).divided(by: x[0], precision: p)
      let result = function == .asec ? try reciprocal.arccosine(precision: p) : try reciprocal.arcsine(precision: p)
      return angleUnit == .degrees ? try toDegrees(result) : result
    case .coth, .sech, .csch:
      try requireWellConditioned(x[0])
      let sinh = try x[0].sinh(precision: p)
      let cosh = try x[0].cosh(precision: p)
      switch function {
      case .coth: return try cosh.divided(by: sinh, precision: p)
      case .sech: return try BigDecimal(1).divided(by: cosh, precision: p)
      default: return try BigDecimal(1).divided(by: sinh, precision: p)
      }
    case .acoth, .asech, .acsch:
      let reciprocal = try BigDecimal(1).divided(by: x[0], precision: p)
      switch function {
      case .acoth: return try reciprocal.atanh(precision: p)
      case .asech: return try reciprocal.acosh(precision: p)
      default: return try reciprocal.asinh(precision: p)
      }
    case .mod:
      guard !x[1].isZero else { throw .divisionByZero }
      let quotient = try x[0].divided(by: x[1], precision: p + 10)
      // Near a multiple of the divisor the floor depends on rounding noise, which the exact engine does not have.
      let fraction = quotient - BigDecimal(quotient.floor)
      let tolerance = BigDecimal(BigInt(1), exponent: -30)
      if fraction.magnitude < tolerance || (BigDecimal(1) - fraction).magnitude < tolerance { throw .domain }
      return x[0] - x[1] * BigDecimal(quotient.floor)
    case .min: return x.dropFirst().reduce(x[0]) { $0 < $1 ? $0 : $1 }
    case .max: return x.dropFirst().reduce(x[0]) { $0 > $1 ? $0 : $1 }
    case .sign:
      // A value this small is rounding noise standing for an exact zero.
      if let order = x[0].decimalOrder, order < -(p - 15) { throw .domain }
      return BigDecimal(x[0].isZero ? 0 : (x[0].isNegative ? -1 : 1))
    case .re, .im, .conj, .arg: throw .notNumeric  // complex values are the other evaluator's job
    case .gcd, .lcm:
      guard x[0].isInteger, x[1].isInteger else { throw .domain }
      let divisor = BigInt.gcd(x[0].floor, x[1].floor)
      if function == .gcd { return BigDecimal(divisor) }
      return divisor.isZero ? BigDecimal(0) : BigDecimal((x[0].floor * x[1].floor).magnitude / divisor)
    }
  }
}
