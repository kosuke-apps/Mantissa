/// The roots of a polynomial with rational coefficients, as exact expressions where there is a closed form that is
/// worth having and as decimals for the rest.
///
/// The steps: a repeated factor is removed, zero is divided out, rational roots are found by the rational root theorem,
/// what is left is solved by the quadratic formula when it is of degree 2, as a polynomial in `x^k` when it has that
/// shape (a biquadratic, `x^3 = 2`), and numerically otherwise.
enum PolynomialRoots {
  struct Roots {
    var exact: [Expr] = []
    var numeric: [ComplexDecimal] = []
  }

  static func solve(_ input: RationalPolynomial) -> Roots {
    var roots = Roots()
    guard input.degree >= 1 else { return roots }
    var polynomial = input.squarefree

    if polynomial[0].isZero {
      roots.exact.append(.zero)
      polynomial = RationalPolynomial(Array(polynomial.coefficients.dropFirst()))
    }

    let (rational, rest) = polynomial.rationalRoots()
    roots.exact += rational.map { .number($0) }
    polynomial = rest

    switch polynomial.degree {
    case ..<1:
      return roots
    case 1:
      roots.exact.append(.number(-polynomial[0] / polynomial[1]))
      return roots
    case 2:
      roots.exact += quadratic(polynomial[2], polynomial[1], polynomial[0])
      return roots
    default:
      break
    }

    // p(x) = q(x^k): solve for u = x^k and take the k-th roots.
    if let (k, inner) = polynomial.substitution, 24 % k == 0 {
      let solved = solve(inner)
      if solved.numeric.isEmpty {
        for u in solved.exact { roots.exact += kthRoots(of: u, k) }
        return roots
      }
    }

    if let numeric = NumericRoots.roots(of: polynomial) { roots.numeric += numeric }
    return roots
  }

  /// The two roots of `ax² + bx + c` (one when the discriminant is zero).
  static func quadratic(_ a: Rational, _ b: Rational, _ c: Rational) -> [Expr] {
    let discriminant = b * b - Rational(4) * a * c
    let scale = Expr.number(Rational(1) / (Rational(2) * a))
    if discriminant.isZero { return [.number(-b / (Rational(2) * a))] }
    let root = Expr.makePower(.number(discriminant), .fraction(1, 2))
    return [
      Expr.makeProduct([scale, Expr.makeSum([.number(-b), root])]),
      Expr.makeProduct([scale, Expr.makeSum([.number(-b), -root])]),
    ]
  }

  /// The `k` roots of `x^k = u`, for `k` dividing 24 (so that the roots of unity are exact): `u^(1/k)` times each
  /// `e^(2πij/k)`, with `u^(1/k)` the principal root (the real one for an odd root of a negative number).
  static func kthRoots(of u: Expr, _ k: Int) -> [Expr] {
    let principal = Expr.makePower(u, .fraction(1, k))
    return (0..<k).map { j in
      let turn = Expr.makeProduct([.number(Rational(2 * j, k)), .pi, .i])
      return Expr.makeProduct([principal, Expr.makePower(.e, turn)])
    }
  }
}
