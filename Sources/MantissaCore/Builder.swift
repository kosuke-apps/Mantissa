/// The unit in which angles are typed and trigonometric results are given.
public enum AngleUnit: Sendable, Equatable {
  case radians
  case degrees
}

/// Turns parsed syntax into a canonical `Expr`, applying the angle unit.
///
/// In degree mode `sin(30)` means 30 degrees, so the argument is multiplied by π/180 on the way in, and `asin(1/2)`
/// gives 30, so the result is multiplied by 180/π on the way out; the π then cancels exactly, which is what lets
/// `sin(30)` be exactly 1/2. A degree sign converts to the working unit: `30°` is 30 in degree mode and π/6 in
/// radian mode, so `sin(30°)` is the same in both. An argument whose text mentions π (`sin(π/6)`) is already an
/// angle in radians, so degree mode leaves it alone rather than reading π/6 as π/6 degrees.
struct Builder {
  var angleUnit: AngleUnit

  private static let degreesToRadians = Expr.fraction(1, 180) * .pi
  private static let radiansToDegrees = Expr.integer(180) * Expr.makePower(.pi, .minusOne)

  func build(_ syntax: Syntax) throws(MathError) -> Expr {
    switch syntax {
    case .number(let value): return .number(value)
    case .symbol(let name): return .symbol(name)
    case .infinity: throw .domain  // ∞ is only an argument of a limit, an integral or a sum
    case .constant(let constant): return .constant(constant)
    case .negate(let operand): return -(try build(operand))
    case .binary(let op, let left, let right):
      let a = try build(left)
      let b = try build(right)
      switch op {
      case .add: return a + b
      case .subtract: return a - b
      case .multiply: return a * b
      case .divide: return try a.divided(by: b)
      case .power: return try a.raised(to: b)
      }
    case .postfix(let op, let operand):
      let value = try build(operand)
      switch op {
      case .factorial: return try Expr.apply(.factorial, [value])
      case .percent: return value * .fraction(1, 100)
      case .degree: return angleUnit == .degrees ? value : value * Builder.degreesToRadians
      }
    case .call(let function, let arguments) where function.isCalculus:
      return try Calculus(builder: self).evaluate(function, arguments)
    case .call(let function, let arguments):
      var built: [Expr] = []
      for argument in arguments { built.append(try build(argument)) }
      return try call(function, built, argumentMentionsPi: arguments.contains { $0.mentionsPi })
    case .radical(let index, let radicand):
      let value = try build(radicand)
      guard let index else { return try value.raised(to: .fraction(1, 2)) }
      return try root(value, index: try build(index))
    }
  }

  private func root(_ value: Expr, index: Expr) throws(MathError) -> Expr {
    try value.raised(to: Expr.one.divided(by: index))
  }

  private func call(_ function: FunctionName, _ x: [Expr], argumentMentionsPi: Bool) throws(MathError) -> Expr {
    switch function {
    case .sin, .cos, .tan:
      let argument = angleUnit == .degrees && !argumentMentionsPi ? x[0] * Builder.degreesToRadians : x[0]
      return try Expr.apply(MathFunction(rawValue: function.rawValue)!, [argument])
    case .cot, .sec, .csc:
      // Written with sine and cosine, so that cot(π/2) is 0 and sec(π/2) is a division by zero, not a domain error of tan.
      let argument = angleUnit == .degrees && !argumentMentionsPi ? x[0] * Builder.degreesToRadians : x[0]
      let sine = try Expr.apply(.sin, [argument])
      let cosine = try Expr.apply(.cos, [argument])
      switch function {
      case .cot: return try cosine.divided(by: sine)
      case .sec: return try Expr.one.divided(by: cosine)
      default: return try Expr.one.divided(by: sine)
      }
    case .asin, .acos, .atan:
      let result = try Expr.apply(MathFunction(rawValue: function.rawValue)!, [x[0]])
      return angleUnit == .degrees ? result * Builder.radiansToDegrees : result
    case .sinh, .cosh, .tanh, .asinh, .acosh, .atanh, .ln, .abs, .floor, .ceil, .round, .gcd, .lcm, .nCr, .nPr:
      return try Expr.apply(MathFunction(rawValue: function.rawValue)!, x)
    case .log:
      return try Expr.apply(.log, [x[0], x.count == 2 ? x[1] : 10])
    case .diff, .int, .lim, .sum: throw .unsupported  // handled before the arguments are built
    case .sqrt: return try x[0].raised(to: .fraction(1, 2))
    case .cbrt: return try x[0].raised(to: .fraction(1, 3))
    case .root: return try root(x[0], index: x[1])
    case .exp: return try Expr.e.raised(to: x[0])
    }
  }
}
