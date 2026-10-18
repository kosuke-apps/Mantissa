// The functions the engine has no case of its own for: each is written with the ones it has.

extension Builder {
  /// An angle in radians, in the unit the calculator is working in.
  func inWorkingUnit(_ radians: Expr) -> Expr {
    angleUnit == .degrees ? radians * Builder.radiansToDegrees : radians
  }

  func derivedCall(_ function: FunctionName, _ x: [Expr]) throws(MathError) -> Expr {
    switch function {
    case .acot: return inWorkingUnit(.pi * .fraction(1, 2) - (try Expr.apply(.atan, [x[0]])))
    case .asec: return inWorkingUnit(try Expr.apply(.acos, [Expr.one.divided(by: x[0])]))
    case .acsc: return inWorkingUnit(try Expr.apply(.asin, [Expr.one.divided(by: x[0])]))
    case .coth: return try Expr.apply(.cosh, [x[0]]).divided(by: Expr.apply(.sinh, [x[0]]))
    case .sech: return try Expr.one.divided(by: Expr.apply(.cosh, [x[0]]))
    case .csch: return try Expr.one.divided(by: Expr.apply(.sinh, [x[0]]))
    case .acoth: return try Expr.apply(.atanh, [Expr.one.divided(by: x[0])])
    case .asech: return try Expr.apply(.acosh, [Expr.one.divided(by: x[0])])
    case .acsch: return try Expr.apply(.asinh, [Expr.one.divided(by: x[0])])
    case .mod:
      let quotient = try x[0].divided(by: x[1])
      return x[0] - x[1] * (try Expr.apply(.floor, [quotient]))
    case .min, .max:
      var best = x[0]
      for next in x.dropFirst() { best = try Builder.extremum(best, next, isMaximum: function == .max) }
      return best
    case .sign:
      if let sign = x[0].numericSign { return .integer(sign) }
      return try x[0].divided(by: Expr.apply(.abs, [x[0]]))
    case .re, .im, .conj, .arg:
      let parts: (real: Expr, imaginary: Expr)
      if x[0].containsImaginaryUnit {
        guard let split = x[0].complexParts() else { throw .unsupported }
        parts = split
      } else {
        parts = (x[0], .zero)  // a letter stands for a real number
      }
      switch function {
      case .re: return parts.real
      case .im: return parts.imaginary
      case .conj: return parts.real - parts.imaginary * .i
      default: return inWorkingUnit(try Builder.angle(y: parts.imaginary, x: parts.real))
      }
    default: throw .unsupported
    }
  }

  /// The larger or the smaller of two real values: chosen by comparing them when they are numbers, and written as
  /// `(a + b ± |a − b|)/2` when they are not.
  private static func extremum(_ a: Expr, _ b: Expr, isMaximum: Bool) throws(MathError) -> Expr {
    if a.containsImaginaryUnit || b.containsImaginaryUnit { throw .domain }
    if let sign = (a - b).numericSign { return (sign >= 0) == isMaximum ? a : b }
    let spread = try Expr.apply(.abs, [a - b])
    return Expr.fraction(1, 2) * (a + b + (isMaximum ? spread : -spread))
  }

  /// The angle of the point (x, y) in radians, in (−π, π]: `atan(y/x)` moved into the right half-plane. It needs to know on
  /// which side of each axis the point lies, so a point with unknowns in it is not supported.
  static func angle(y: Expr, x: Expr) throws(MathError) -> Expr {
    guard let signOfX = x.numericSign, let signOfY = y.numericSign else { throw .unsupported }
    if signOfX == 0 {
      if signOfY == 0 { throw .noValue }  // the origin has no direction
      return (signOfY > 0 ? Expr.one : Expr.minusOne) * .pi * .fraction(1, 2)
    }
    let base = try Expr.apply(.atan, [y.divided(by: x)])
    if signOfX > 0 { return base }
    return signOfY >= 0 ? base + .pi : base - .pi
  }
}
