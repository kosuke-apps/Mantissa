// Greatest common divisors, repeated factors and perfect squares of polynomials in several unknowns.

extension MultiPolynomial {
  /// The greatest common divisor of the coefficients of the powers of the unknown at `index`: the part of the polynomial
  /// that does not depend on it and that every term shares.
  func content(in index: Int) -> MultiPolynomial {
    var result = zero
    for coefficient in coefficients(in: index) where !coefficient.isZero {
      result = result.isZero ? coefficient.normalized : MultiPolynomial.gcd(result, coefficient)
      if result.isConstant { return one }
    }
    return result
  }

  /// The polynomial divided by its content in the unknown at `index`.
  func primitivePart(in index: Int) -> MultiPolynomial {
    let common = content(in: index)
    return dividedExactly(by: common) ?? self
  }

  /// The remainder of `lc(divisor)^k · self` divided by `divisor`, as polynomials in the unknown at `index`, which needs no
  /// division of coefficients.
  func pseudoRemainder(by divisor: MultiPolynomial, in index: Int) -> MultiPolynomial {
    let divisorDegree = divisor.degree(in: index)
    let divisorLead = divisor.coefficients(in: index)[divisorDegree]
    var remainder = self
    while !remainder.isZero, !ring.isExhausted {
      let remainderDegree = remainder.degree(in: index)
      if remainderDegree < divisorDegree { break }
      let remainderLead = remainder.coefficients(in: index)[remainderDegree]
      remainder =
        divisorLead * remainder
        - (remainderLead * divisor).multiplied(byVariable: index, power: remainderDegree - divisorDegree)
      // Only the remainder up to a number is wanted, and its coefficients would otherwise grow with every step.
      remainder = remainder.normalized
    }
    return remainder
  }

  /// A greatest common divisor with whole-number coefficients and a positive leading coefficient; 1 when there is no common
  /// factor.
  static func gcd(_ a: MultiPolynomial, _ b: MultiPolynomial) -> MultiPolynomial {
    if a.isZero { return b.normalized }
    if b.isZero { return a.normalized }
    guard let index = a.names.indices.first(where: { a.degree(in: $0) > 0 || b.degree(in: $0) > 0 }) else {
      return a.one
    }
    if a.degree(in: index) == 0 { return gcd(a, b.content(in: index)) }
    if b.degree(in: index) == 0 { return gcd(a.content(in: index), b) }

    let contentA = a.content(in: index)
    let contentB = b.content(in: index)
    guard var x = a.dividedExactly(by: contentA), var y = b.dividedExactly(by: contentB) else { return a.one }
    let common = gcd(contentA, contentB)
    if x.degree(in: index) < y.degree(in: index) { swap(&x, &y) }

    var steps = 0
    while true {
      let remainder = x.pseudoRemainder(by: y, in: index)
      if remainder.isZero { break }
      if remainder.degree(in: index) == 0 {
        y = a.one
        break
      }
      x = y
      y = remainder.primitivePart(in: index)
      steps += 1
      if steps > 64 || a.ring.isExhausted { return a.one }
    }
    return (common * y).normalized
  }

  // MARK: Repeated factors

  /// `self = coefficient · Π baseᵉ`, where the bases are squarefree, have no factor in common, and are not constant, each with
  /// whole coefficients and a positive leading one. The bases are in no particular order.
  func squarefreeDecomposition() -> (coefficient: Rational, factors: [(base: MultiPolynomial, power: Int)]) {
    guard !isZero else { return (Rational(0), []) }
    let (primitive, scale) = normalizedWithContent
    var factors: [(base: MultiPolynomial, power: Int)] = []
    primitive.collectSquarefreeFactors(into: &factors)

    // The bases are scaled to whole numbers with a positive leading coefficient, so the number in front is what is left.
    var product = primitive.one
    for (base, power) in factors { product = product * base.power(power) }
    guard let ratio = primitive.dividedExactly(by: product), let number = ratio.constantValue, !number.isZero
    else { return (scale, [(primitive, 1)]) }
    return (scale * number, factors)
  }

  private func collectSquarefreeFactors(into result: inout [(base: MultiPolynomial, power: Int)]) {
    guard !isConstant, let index = names.indices.first(where: { degree(in: $0) > 0 }) else { return }
    func add(_ base: MultiPolynomial, _ power: Int) {
      let normal = base.normalized
      guard !normal.isConstant else { return }
      if let existing = result.firstIndex(where: { $0.base == normal }) {
        result[existing].power += power
      } else {
        result.append((normal, power))
      }
    }

    // What every term shares (a monomial, or any polynomial without this unknown) is dealt with on its own.
    let shared = content(in: index)
    if !shared.isConstant {
      var inner: [(base: MultiPolynomial, power: Int)] = []
      shared.collectSquarefreeFactors(into: &inner)
      for (base, power) in inner { add(base, power) }
    }
    guard let rest = dividedExactly(by: shared), rest.degree(in: index) > 0 else { return }

    // Yun's algorithm: f = Π aᵢ^i, where aᵢ is the product of the factors that occur exactly i times.
    let derivative = rest.derivative(in: index)
    let repeated = MultiPolynomial.gcd(rest, derivative)
    guard var b = rest.dividedExactly(by: repeated), var c = derivative.dividedExactly(by: repeated) else {
      add(rest, 1)
      return
    }
    var d = c - b.derivative(in: index)
    var power = 1
    while !b.isConstant, power <= 64, !ring.isExhausted {
      let a = MultiPolynomial.gcd(b, d)
      if !a.isConstant { add(a, power) }
      guard let nextB = b.dividedExactly(by: a), let nextC = d.dividedExactly(by: a) else {
        add(b, power)
        return
      }
      b = nextB
      c = nextC
      d = c - b.derivative(in: index)
      power += 1
    }
  }

  // MARK: Perfect squares

  /// The polynomial whose square this is, when there is one.
  func exactSquareRoot() -> MultiPolynomial? {
    guard let lead = leadingMonomial, lead.allSatisfy({ $0 % 2 == 0 }),
      let leadRoot = leadingCoefficient.exactSquareRoot
    else { return nil }
    var root = MultiPolynomial(ring: ring, terms: [lead.map { $0 / 2 }: leadRoot])
    var remainder = self - root * root
    var steps = 0
    while let top = remainder.leadingMonomial {
      steps += 1
      if steps > 500 || ring.isExhausted { return nil }
      guard let rootLead = root.leadingMonomial else { return nil }
      var next = top
      for index in next.indices {
        next[index] -= rootLead[index]
        if next[index] < 0 { return nil }
      }
      let coefficient = remainder.terms[top]! / (Rational(2) * root.leadingCoefficient)
      root = root + MultiPolynomial(ring: ring, terms: [next: coefficient])
      remainder = self - root * root
    }
    return root
  }
}

extension Rational {
  /// The positive or zero number whose square this is, when it is a perfect square.
  var exactSquareRoot: Rational? {
    guard !isNegative else { return nil }
    let top = numerator.integerSquareRoot()
    let bottom = denominator.integerSquareRoot()
    guard top * top == numerator, bottom * bottom == denominator else { return nil }
    return Rational(top, bottom)
  }
}
