// Trigonometric identities that make an expression smaller: sin² + cos² = 1, the double-angle forms, and the like.
//
// The canonical form does not know them (it keeps `sin(x)^2 + cos(x)^2` as it is), so they are applied to a finished
// expression, bottom up, and the result is used only when it is smaller.

extension Expr {
  /// The expression with sums of sine and cosine squares and products of sine and cosine rewritten, or `nil` when that gives
  /// nothing smaller (the same size counts: 4 sin x cos x is 2 sin 2x):
  ///
  /// - `a sin²u + a cos²u` is `a`, and `a − a sin²u` is `a cos²u`, `a − a cos²u` is `a sin²u`;
  /// - `a cos²u − a sin²u`, `a − 2a sin²u` and `2a cos²u − a` are `a cos 2u`;
  /// - `2a sin u cos u` is `a sin 2u`.
  ///
  /// Here `a` stands for any product that does not depend on the kind of term (a number, `x`, `e^x`), the same in both terms.
  public func trigonometricallySimplified() -> Expr? {
    guard !freeSymbols.isEmpty || nodeCount > 1 else { return nil }
    let result = simplifiedTrigonometry()
    return result != self && result.nodeCount <= nodeCount ? result : nil
  }

  private func simplifiedTrigonometry() -> Expr {
    switch self {
    case .number, .constant, .symbol: return self
    case .sum(let terms): return Expr.simplifiedTrigonometrySum(terms.map { $0.simplifiedTrigonometry() })
    case .product(let factors):
      // A product on its own is a sum of one term, so that 2 sin u cos u is found.
      return Expr.simplifiedTrigonometrySum([Expr.makeProduct(factors.map { $0.simplifiedTrigonometry() })])
    case .power(let base, let exponent):
      return Expr.makePower(base.simplifiedTrigonometry(), exponent.simplifiedTrigonometry())
    case .function(let function, let arguments):
      return (try? Expr.apply(function, arguments.map { $0.simplifiedTrigonometry() })) ?? self
    }
  }

  private struct SquareKey: Hashable {
    var rest: Expr
    var angle: Expr
  }

  private static func simplifiedTrigonometrySum(_ terms: [Expr]) -> Expr {
    // Each term is a number times a product that is a sine square, a cosine square or neither (the rest of the product is
    // what two terms must share to combine).
    var plain: [Expr: Rational] = [:]
    var sines: [SquareKey: Rational] = [:]
    var cosines: [SquareKey: Rational] = [:]
    var extra: [Expr] = []
    var changed = false

    for term in terms {
      // A plain number is its own coefficient, with nothing else in the term.
      var (coefficient, body) = term.splitCoefficient()
      if case .number(let value) = term { (coefficient, body) = (value, .one) }
      let factors: [Expr]
      if case .product(let parts) = body { factors = parts } else { factors = [body] }

      // 2 sin u cos u
      if let (angle, remaining) = sineAndCosine(in: factors), let half = halved(coefficient) {
        if let double = try? Expr.apply(.sin, [makeProduct([.integer(2), angle])]) {
          extra.append(makeProduct([.number(half), makeProduct(remaining), double]))
          changed = true
          continue
        }
      }

      if let (isSine, angle, remaining) = square(in: factors) {
        let key = SquareKey(rest: makeProduct(remaining), angle: angle)
        if isSine {
          sines[key, default: Rational(0)] += coefficient
        } else {
          cosines[key, default: Rational(0)] += coefficient
        }
      } else {
        plain[body, default: Rational(0)] += coefficient
      }
    }

    for key in Set(sines.keys).union(cosines.keys) {
      var s = sines[key] ?? Rational(0)
      var c = cosines[key] ?? Rational(0)
      var p = plain[key.rest] ?? Rational(0)
      let double = { () -> Expr? in try? Expr.apply(.cos, [makeProduct([.integer(2), key.angle])]) }

      if !s.isZero && s == c {
        // a sin² + a cos² = a
        p += s
        s = Rational(0)
        c = Rational(0)
        changed = true
      } else if !s.isZero && s == -c, let cos2 = double() {
        // a cos² − a sin² = a cos 2u
        extra.append(makeProduct([.number(c), key.rest, cos2]))
        s = Rational(0)
        c = Rational(0)
        changed = true
      } else if !s.isZero, !p.isZero, s == -p * Rational(2), let cos2 = double() {
        // a − 2a sin² = a cos 2u
        extra.append(makeProduct([.number(p), key.rest, cos2]))
        s = Rational(0)
        p = Rational(0)
        changed = true
      } else if !c.isZero, !p.isZero, c == -p * Rational(2), let cos2 = double() {
        // 2a cos² − a = a cos 2u
        extra.append(makeProduct([.number(-p), key.rest, cos2]))
        c = Rational(0)
        p = Rational(0)
        changed = true
      } else if !s.isZero, !p.isZero, s == -p {
        // a − a sin² = a cos²
        c += p
        s = Rational(0)
        p = Rational(0)
        changed = true
      } else if !c.isZero, !p.isZero, c == -p {
        // a − a cos² = a sin²
        s += p
        c = Rational(0)
        p = Rational(0)
        changed = true
      }
      sines[key] = s
      cosines[key] = c
      plain[key.rest] = p
    }
    guard changed else { return makeSum(terms) }

    var rebuilt: [Expr] = extra
    for (rest, coefficient) in plain where !coefficient.isZero {
      rebuilt.append(makeProduct([.number(coefficient), rest]))
    }
    for (key, coefficient) in sines where !coefficient.isZero {
      let square = makePower(.function(.sin, [key.angle]), .integer(2))
      rebuilt.append(makeProduct([.number(coefficient), key.rest, square]))
    }
    for (key, coefficient) in cosines where !coefficient.isZero {
      let square = makePower(.function(.cos, [key.angle]), .integer(2))
      rebuilt.append(makeProduct([.number(coefficient), key.rest, square]))
    }
    return makeSum(rebuilt)
  }

  /// Half of `coefficient` when it is an even whole number.
  private static func halved(_ coefficient: Rational) -> Rational? {
    guard coefficient.isInteger, coefficient.numerator.isEven, !coefficient.isZero else { return nil }
    return coefficient / Rational(2)
  }

  /// A sine square or a cosine square among the factors: whether it is a sine, its angle, and the other factors.
  private static func square(in factors: [Expr]) -> (Bool, Expr, [Expr])? {
    for (index, factor) in factors.enumerated() {
      guard case .power(.function(let function, let arguments), let exponent) = factor, exponent == .integer(2),
        function == .sin || function == .cos
      else { continue }
      var remaining = factors
      remaining.remove(at: index)
      return (function == .sin, arguments[0], remaining)
    }
    return nil
  }

  /// A sine and a cosine of the same angle among the factors, and the other factors.
  private static func sineAndCosine(in factors: [Expr]) -> (Expr, [Expr])? {
    for (sineIndex, factor) in factors.enumerated() {
      guard case .function(.sin, let arguments) = factor else { continue }
      guard let cosineIndex = factors.firstIndex(of: .function(.cos, arguments)) else { continue }
      var remaining = factors
      remaining.remove(at: max(sineIndex, cosineIndex))
      remaining.remove(at: min(sineIndex, cosineIndex))
      return (arguments[0], remaining)
    }
    return nil
  }
}
