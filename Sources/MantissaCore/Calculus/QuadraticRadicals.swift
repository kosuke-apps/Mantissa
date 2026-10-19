// Integrals with the square root of a quadratic: ∫ N(x) √S dx, ∫ N(x)/√S dx and ∫ N(x)/(S√S) dx for a polynomial N and a
// quadratic S = ax² + bx + c with rational coefficients (√(1 − x²), x²/√(x² + 1), √(x² − 1), 1/(x² + 1)^(3/2)).
//
// The answer has a known shape, `Q(x)·√S + λ ∫ dx/√S` with `Q` a polynomial of one degree less than the numerator, and the
// unknown coefficients come from differentiating that and comparing with the integrand, which is a small linear system. The
// last integral is the one basic integral of the family, inverse hyperbolic sine, logarithm or arcsine according to the signs.

enum QuadraticRadicals {
  /// An antiderivative of `f`, or `nil` when `f` is not of one of those forms.
  static func antiderivative(of f: Expr, variable: String) -> Expr? {
    let factors: [Expr]
    if case .product(let inner) = f { factors = inner } else { factors = [f] }

    var radical: (base: Expr, odd: Int, quadratic: [Rational])?
    var rest: [Expr] = []
    for factor in factors {
      if radical == nil, case .power(let base, let exponent) = factor, let e = exponent.rational,
        e.denominator == BigInt(2), let odd = e.numerator.asInt, let polynomial = base.polynomial(in: variable),
        polynomial.degree == 2, let coefficients = polynomial.rationalCoefficients
      {
        radical = (base, odd, coefficients)
      } else {
        rest.append(factor)
      }
    }
    guard let radical else { return nil }
    let s = RationalPolynomial(radical.quadratic)
    let x = Expr.symbol(variable)
    let root = Expr.makePower(radical.base, .fraction(1, 2))

    // The rest of the product: constants, a polynomial, and perhaps 1/x or 1/x².
    var constants: [Expr] = []
    var polynomialFactors: [Expr] = []
    var inverse = 0
    for factor in rest {
      if !factor.contains(variable) {
        constants.append(factor)
      } else if inverse == 0, case .power(let base, let exponent) = factor, base == x, let n = exponent.rational,
        n.isInteger, let whole = n.numerator.asInt, whole == -1 || whole == -2
      {
        inverse = -whole
      } else {
        polynomialFactors.append(factor)
      }
    }
    guard let numerator = Expr.makeProduct(polynomialFactors).polynomial(in: variable),
      let n = numerator.rationalCoefficients
    else { return nil }
    let scale = Expr.makeProduct(constants)

    if inverse > 0 {
      guard radical.odd >= -1 else { return nil }
      // N·S^((odd+1)/2)/(x^j √S) is a polynomial over √S plus the terms with 1/x and 1/x².
      var top = RationalPolynomial(n)
      for _ in 0..<((radical.odd + 1) / 2) { top = RationalPolynomial.product(top, s) }
      var parts: [Expr] = []
      let polynomialPart = RationalPolynomial(Array(top.coefficients.dropFirst(inverse)))
      if !polynomialPart.isZero {
        guard let (q, lambda) = solve(polynomialPart, s, sign: 1) else { return nil }
        parts.append(Expr.makeProduct([expression(of: q, x), root]))
        if !lambda.isZero {
          guard let base = inverseRootIntegral(s, x) else { return nil }
          parts.append(Expr.makeProduct([.number(lambda), base]))
        }
      }
      for power in 1...inverse {
        // The coefficient of x^(−power) in the integrand.
        let coefficient = top[inverse - power]
        if coefficient.isZero { continue }
        guard let integral = reciprocalPowerTimesInverseRoot(power, s, x, radical.base) else { return nil }
        parts.append(Expr.makeProduct([.number(coefficient), integral]))
      }
      return Expr.makeProduct([scale, Expr.makeSum(parts)])
    }

    switch radical.odd {
    case let odd where odd >= -1:
      // N·S^(odd/2) = N·S^((odd+1)/2) / √S
      var top = RationalPolynomial(n)
      for _ in 0..<((odd + 1) / 2) { top = RationalPolynomial.product(top, s) }
      guard let (q, lambda) = solve(top, s, sign: 1) else { return nil }
      var parts = [Expr.makeProduct([expression(of: q, x), root])]
      if !lambda.isZero {
        guard let base = inverseRootIntegral(s, x) else { return nil }
        parts.append(Expr.makeProduct([.number(lambda), base]))
      }
      return Expr.makeProduct([scale, Expr.makeSum(parts)])

    case -3:
      // N/(S√S): the shape is Q/√S + λ∫dx/√S.
      guard let (q, lambda) = solve(RationalPolynomial(n), s, sign: -1) else { return nil }
      let inverseRoot = Expr.makePower(radical.base, .fraction(-1, 2))
      var parts = [Expr.makeProduct([expression(of: q, x), inverseRoot])]
      if !lambda.isZero {
        guard let base = inverseRootIntegral(s, x) else { return nil }
        parts.append(Expr.makeProduct([.number(lambda), base]))
      }
      return Expr.makeProduct([scale, Expr.makeSum(parts)])

    default:
      return nil
    }
  }

  // MARK: The linear system

  /// `Q` and `λ` with `N = Q′S + ½QS′ + λ` (`sign` 1, for `Q√S`) or `N = Q′S − ½QS′ + λS` (`sign` −1, for `Q/√S`).
  private static func solve(
    _ numerator: RationalPolynomial, _ s: RationalPolynomial, sign: Int
  ) -> (
    RationalPolynomial, Rational
  )? {
    let degreeOfQ = sign > 0 ? max(numerator.degree - 1, -1) : max(numerator.degree - 1, 1)
    let unknowns = degreeOfQ + 2  // the coefficients of Q, then λ
    let equations = max(numerator.degree, degreeOfQ + 1, 2) + 1
    let half = Rational(sign, 2)
    let sPrime = s.derivative

    // The image of each unknown: for q_k, the polynomial (x^k)′S + half·x^k·S′; for λ, 1 or S.
    var columns: [RationalPolynomial] = []
    if degreeOfQ >= 0 {
      for k in 0...degreeOfQ {
        var monomial = Array(repeating: Rational(0), count: k + 1)
        monomial[k] = Rational(1)
        let power = RationalPolynomial(monomial)
        let derived = RationalPolynomial.product(power.derivative, s)
        let scaled = RationalPolynomial(RationalPolynomial.product(power, sPrime).coefficients.map { $0 * half })
        columns.append(add(derived, scaled))
      }
    }
    columns.append(sign > 0 ? RationalPolynomial([Rational(1)]) : s)

    var matrix = (0..<equations).map { row in columns.map { $0[row] } + [numerator[row]] }
    // Gaussian elimination.
    var pivotRow = 0
    var pivots: [Int] = []
    for column in 0..<unknowns {
      guard let found = (pivotRow..<equations).first(where: { !matrix[$0][column].isZero }) else { continue }
      matrix.swapAt(pivotRow, found)
      let pivot = matrix[pivotRow][column]
      matrix[pivotRow] = matrix[pivotRow].map { $0 / pivot }
      for row in 0..<equations where row != pivotRow && !matrix[row][column].isZero {
        let factor = matrix[row][column]
        for index in 0...unknowns { matrix[row][index] -= factor * matrix[pivotRow][index] }
      }
      pivots.append(column)
      pivotRow += 1
    }
    // A row of zeros equal to something is a system without a solution.
    for row in pivotRow..<equations where !matrix[row][unknowns].isZero { return nil }
    guard pivots.count == unknowns else { return nil }
    let solution = pivots.enumerated().map { matrix[$0.offset][unknowns] }
    return (RationalPolynomial(Array(solution.prefix(degreeOfQ + 1))), solution[unknowns - 1])
  }

  private static func add(_ a: RationalPolynomial, _ b: RationalPolynomial) -> RationalPolynomial {
    let count = max(a.coefficients.count, b.coefficients.count)
    return RationalPolynomial((0..<count).map { a[$0] + b[$0] })
  }

  private static func expression(of polynomial: RationalPolynomial, _ x: Expr) -> Expr {
    Expr.makeSum(
      polynomial.coefficients.enumerated().map { power, coefficient in
        Expr.makeProduct([.number(coefficient), Expr.makePower(x, .integer(power))])
      })
  }

  // MARK: ∫ dx/(x√S) and ∫ dx/(x²√S)

  /// `∫ dx/(x^j √S)` for `j` 1 or 2 and `S = ax² + bx + c` with `c ≠ 0`.
  private static func reciprocalPowerTimesInverseRoot(
    _ j: Int, _ s: RationalPolynomial, _ x: Expr, _ base: Expr
  ) -> Expr? {
    let (c, b, a) = (s[0], s[1], s[2])
    guard !c.isZero else { return nil }
    let root = Expr.makePower(base, .fraction(1, 2))
    func reciprocalRoot(_ value: Rational) -> Expr { Expr.makePower(.number(value), .fraction(-1, 2)) }

    // ∫ dx/(x√S)
    let first: Expr
    if c.signum > 0 {
      // −(1/√c) ln|(c + bx/2 + √c √S)/x|, half of the usual form inside the logarithm, which is a constant apart
      let inside = Expr.makeProduct([
        Expr.makeSum([
          .number(c), Expr.makeProduct([.number(b / Rational(2)), x]),
          Expr.makeProduct([Expr.makePower(.number(c), .fraction(1, 2)), root]),
        ]),
        Expr.makePower(x, .minusOne),
      ])
      guard let magnitude = try? Expr.apply(.abs, [inside]), let logarithm = try? Expr.apply(.ln, [magnitude])
      else { return nil }
      first = Expr.makeProduct([.minusOne, reciprocalRoot(c), logarithm])
    } else {
      // (1/√−c) asin((bx + 2c)/(|x|√(b² − 4ac)))
      let discriminant = b * b - Rational(4) * a * c
      guard discriminant.signum > 0, let magnitude = try? Expr.apply(.abs, [x]) else { return nil }
      let argument = Expr.makeProduct([
        Expr.makeSum([Expr.makeProduct([.number(b), x]), .number(Rational(2) * c)]),
        Expr.makePower(magnitude, .minusOne), reciprocalRoot(discriminant),
      ])
      guard let function = try? Expr.apply(.asin, [argument]) else { return nil }
      first = Expr.makeProduct([reciprocalRoot(-c), function])
    }
    if j == 1 { return first }

    // ∫ dx/(x²√S) = −√S/(c x) − (b/2c) ∫ dx/(x√S)
    let leading = Expr.makeProduct([.number(-c.reciprocal), root, Expr.makePower(x, .minusOne)])
    return Expr.makeSum([leading, Expr.makeProduct([.number(-b / (Rational(2) * c)), first])])
  }

  // MARK: ∫ dx/√S

  /// `∫ dx/√(ax² + bx + c)`: `asinh` when `a > 0` and the discriminant is negative, a logarithm when it is positive, `asin` when
  /// `a < 0`.
  private static func inverseRootIntegral(_ s: RationalPolynomial, _ x: Expr) -> Expr? {
    let (c, b, a) = (s[0], s[1], s[2])
    let discriminant = b * b - Rational(4) * a * c
    func root(_ value: Rational) -> Expr { Expr.makePower(.number(value), .fraction(1, 2)) }
    func reciprocalRoot(_ value: Rational) -> Expr { Expr.makePower(.number(value), .fraction(-1, 2)) }

    let linear = Expr.makeSum([Expr.makeProduct([.number(Rational(2) * a), x]), .number(b)])
    if a.signum > 0 {
      if discriminant.signum < 0 {
        let argument = Expr.makeProduct([linear, reciprocalRoot(-discriminant)])
        guard let function = try? Expr.apply(.asinh, [argument]) else { return nil }
        return Expr.makeProduct([reciprocalRoot(a), function])
      }
      if discriminant.signum > 0 {
        // ln|ax + b/2 + √a √S|, which differs from ln|2ax + b + 2√a √S| by a constant
        let sExpression = expression(of: s, x)
        let inside = Expr.makeSum([
          Expr.makeProduct([.number(a), x]), .number(b / Rational(2)),
          Expr.makeProduct([root(a), Expr.makePower(sExpression, .fraction(1, 2))]),
        ])
        guard let magnitude = try? Expr.apply(.abs, [inside]), let logarithm = try? Expr.apply(.ln, [magnitude])
        else { return nil }
        return Expr.makeProduct([reciprocalRoot(a), logarithm])
      }
      return nil
    }
    guard a.signum < 0, discriminant.signum > 0 else { return nil }
    // (1/√−a) asin((−2ax − b)/√(b² − 4ac))
    let argument = Expr.makeProduct([.minusOne, linear, reciprocalRoot(discriminant)])
    guard let function = try? Expr.apply(.asin, [argument]) else { return nil }
    return Expr.makeProduct([reciprocalRoot(-a), function])
  }
}
