// Trigonometric simplification by algebra: with `s = sin u` and `c = cos u` (and `tan u = s/c`) an expression in one angle is
// a rational function of s and c, and s² + c² = 1 lets every s² be written as 1 − c² (or every c² as 1 − s²). What is left
// is a polynomial that has at most the first power of s, so that two such fractions are equal exactly when they have the same
// reduced form, and a common factor can be cancelled: tan x cos x is sin x, (1 − cos² x)/sin x is sin x, and
// 1/cos² x − tan² x is 1.

extension Expr {
  /// The expression rewritten through `sin² + cos² = 1` and with the common factors of numerator and denominator cancelled,
  /// when that is smaller; `nil` when the expression has trigonometric functions of more than one angle, a function other
  /// than polynomial in them, or nothing is gained.
  public func trigonometricallyReduced() -> Expr? {
    guard nodeCount <= 150 else { return nil }
    func isTrigonometric(_ part: Expr) -> Bool {
      if case .function(let function, _) = part { return function == .sin || function == .cos || function == .tan }
      return false
    }
    // The one angle.
    var angle: Expr?
    for part in collectAll(where: isTrigonometric) {
      guard case .function(_, let arguments) = part else { continue }
      if let known = angle, known != arguments[0] { return nil }
      if !arguments[0].collectAll(where: isTrigonometric).isEmpty { return nil }
      angle = arguments[0]
    }
    guard let angle else { return nil }

    let sine = Expr.symbol("s#")
    let cosine = Expr.symbol("c#")
    guard
      let rewritten = replacing({ part in
        guard case .function(let function, let arguments) = part, arguments[0] == angle else { return nil }
        switch function {
        case .sin: return sine
        case .cos: return cosine
        case .tan: return Expr.makeProduct([sine, Expr.makePower(cosine, .minusOne)])
        default: return nil
        }
      })
    else { return nil }

    // Both letters are always there, even when one has cancelled away (tan x cos x is s).
    let names = rewritten.freeSymbols.union(["s#", "c#"]).sorted()
    guard names.count <= 4, let sineIndex = names.firstIndex(of: "s#"), let cosineIndex = names.firstIndex(of: "c#"),
      let (numerator, denominators) = rewritten.together(variables: Set(names))
    else { return nil }
    var bottom = Expr.one
    for (base, power) in denominators { bottom = bottom * Expr.makePower(base, .integer(power)) }

    // The two ways of reducing: no s² (every s² is 1 − c²), or no c² (every c² is 1 − s²).
    var best: Expr?
    for (eliminated, kept) in [(sineIndex, cosineIndex), (cosineIndex, sineIndex)] {
      let ring = PolynomialRing(names: names, budget: 30_000)
      guard let top = MultiPolynomial(numerator, ring: ring), let low = MultiPolynomial(bottom, ring: ring),
        !low.isZero
      else { return nil }
      let one = top.one
      let square = one - MultiPolynomial.variable(kept, ring: ring).power(2)
      var reducedTop = top.replacingSquares(of: eliminated, with: square)
      var reducedLow = low.replacingSquares(of: eliminated, with: square)
      guard !reducedLow.isZero else { continue }
      let common = MultiPolynomial.gcd(reducedTop, reducedLow)
      if !common.isConstant, let newTop = reducedTop.dividedExactly(by: common),
        let newLow = reducedLow.dividedExactly(by: common)
      {
        reducedTop = newTop
        reducedLow = newLow
      }
      guard !ring.isExhausted else { continue }

      let (topPart, topContent) = reducedTop.normalizedWithContent
      let (lowPart, lowContent) = reducedLow.normalizedWithContent
      var factors: [Expr] = [.number(topContent / lowContent), topPart.expression]
      if !lowPart.isConstant { factors.append(Expr.makePower(lowPart.expression, .minusOne)) }
      let result = Expr.makeProduct(factors)
      guard
        let restored = result.replacing({ part in
          if part == sine { return .function(.sin, [angle]) }
          if part == cosine { return .function(.cos, [angle]) }
          return nil
        })
      else { continue }
      if best == nil || restored.nodeCount < best!.nodeCount { best = restored }
    }
    guard let best, best != self, best.nodeCount < nodeCount else { return nil }
    return best
  }
}

extension Expr {
  /// The expression with every trigonometric simplification applied until nothing more is gained: the identities of
  /// `trigonometricallySimplified` and the algebra of `trigonometricallyReduced`, one after the other (1 + 2 sin x cos x is
  /// 1 + sin 2x, once (sin x + cos x)² has been multiplied out).
  public func trigonometricallyTidied() -> Expr {
    var current = self
    for _ in 0..<3 {
      var changed = false
      if let reduced = current.trigonometricallyReduced() {
        current = reduced
        changed = true
      }
      if let simplified = current.trigonometricallySimplified() {
        current = simplified
        changed = true
      }
      if !changed { break }
    }
    return current
  }
}

extension MultiPolynomial {
  /// The polynomial with every square of the unknown at `index` replaced by `replacement`: `x³` is `x · replacement`, `x⁴` is
  /// `replacement²`. What is left has the unknown to the first power at most.
  func replacingSquares(of index: Int, with replacement: MultiPolynomial) -> MultiPolynomial {
    var result = zero
    var powers: [Int: MultiPolynomial] = [:]
    for (monomial, coefficient) in terms {
      var rest = monomial
      let exponent = rest[index]
      rest[index] = exponent % 2
      let pairs = exponent / 2
      var term = MultiPolynomial(ring: ring, terms: [rest: coefficient])
      if pairs > 0 {
        if powers[pairs] == nil { powers[pairs] = replacement.power(pairs) }
        term = term * powers[pairs]!
      }
      result = result + term
    }
    return result
  }
}
