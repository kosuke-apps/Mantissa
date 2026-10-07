import Testing

@testable import MantissaCore

@Suite("Expr")
struct ExprTests {
  private let x = Expr.symbol("x")
  private let y = Expr.symbol("y")
  private let half = Expr.fraction(1, 2)

  @Test("Sums collect like terms and drop zeros")
  func sums() {
    #expect(x + x == Expr.integer(2) * x)
    #expect(x - x == .zero)
    #expect((x + y) - y == x)
    #expect(Expr.integer(3) * x + Expr.integer(2) * x == Expr.integer(5) * x)
    #expect(x + 1 + 2 == x + 3)
    #expect(x + y == y + x)
    #expect((x + y) + (x + y) == Expr.integer(2) * x + Expr.integer(2) * y)
    #expect(.pi + .pi == Expr.integer(2) * .pi)
    #expect(Expr.integer(1) + Expr.integer(2) == Expr.integer(3))
  }

  @Test("Products merge equal bases and keep one coefficient")
  func products() throws {
    #expect(x * x == (try x.raised(to: 2)))
    #expect(x * y == y * x)
    #expect(Expr.integer(2) * x * Expr.integer(3) == Expr.integer(6) * x)
    #expect(x * Expr.zero == .zero)
    #expect(x * .one == x)
    #expect(try (x * y).raised(to: 2) == (try x.raised(to: 2)) * (try y.raised(to: 2)))
    #expect(try x.divided(by: x) == .one)
    #expect(try (x * y).divided(by: y) == x)
    #expect(
      try Expr.integer(2).raised(to: x) * Expr.integer(2).raised(to: y) == (try Expr.integer(2).raised(to: x + y)))
    #expect(Expr.e.raised(toUnchecked: x) * Expr.e.raised(toUnchecked: -x) == .one)
  }

  @Test("A number multiplies through a sum")
  func distribution() {
    #expect(Expr.integer(2) * (x + 1) == Expr.integer(2) * x + 2)
    #expect(half * (x + y) == half * x + half * y)
    #expect(Expr.integer(-1) * (x - y) == y - x)
    #expect(-(x + 1) == -x - 1)
  }

  @Test("Powers of numbers are exact, and roots become prime radicals")
  func numberPowers() throws {
    func power(_ base: Int, _ exponent: Expr) throws -> Expr { try Expr.integer(base).raised(to: exponent) }
    #expect(try power(2, 10) == Expr.integer(1024))
    #expect(try power(2, -3) == Expr.fraction(1, 8))
    #expect(try power(4, half) == Expr.integer(2))
    #expect(try power(8, Expr.fraction(1, 3)) == Expr.integer(2))
    #expect(try power(8, Expr.fraction(2, 3)) == Expr.integer(4))
    #expect(try power(-8, Expr.fraction(1, 3)) == Expr.integer(-2))
    #expect(try power(12, half) == Expr.integer(2) * (try power(3, half)))
    #expect(try power(2, half) * (try power(2, half)) == Expr.integer(2))
    #expect(try power(2, Expr.fraction(5, 4)) == Expr.integer(2) * (try power(2, Expr.fraction(1, 4))))
    #expect(try power(2, Expr.fraction(-1, 2)) == half * (try power(2, half)))
    #expect(try power(6, half) == (try power(2, half)) * (try power(3, half)))
    // An even root of a negative number is not real: it stays as written.
    #expect(try power(-4, half) == .power(.integer(-4), half))
  }

  @Test("Powers of powers: only the safe simplifications are made")
  func powerOfPower() throws {
    // (x²)^(1/2) is |x|, not x, so it must not become x.
    #expect(try x.raised(to: 2).raised(to: half) != x)
    #expect(try x.raised(to: half).raised(to: 2) == x)
    #expect(try x.raised(to: 2).raised(to: 3) == (try x.raised(to: 6)))
    #expect(try Expr.pi.raised(to: 2).raised(to: half) == .pi)
    #expect(try Expr.e.raised(to: x).raised(to: 2) == (try Expr.e.raised(to: Expr.integer(2) * x)))
  }

  @Test("0 and 1 as bases and exponents")
  func specialValues() throws {
    #expect(try Expr.zero.raised(to: 3) == .zero)
    #expect(try Expr.one.raised(to: x) == .one)
    #expect(try x.raised(to: 0) == .one)
    #expect(try x.raised(to: 1) == x)
    #expect(throws: MathError.domain) { try Expr.zero.raised(to: 0) }
    #expect(throws: MathError.divisionByZero) { try Expr.zero.raised(to: -1) }
    #expect(throws: MathError.divisionByZero) { try Expr.one.divided(by: .zero) }
    #expect(throws: MathError.divisionByZero) { try x.divided(by: x - x) }
  }

  @Test("Rebuilding a canonical expression changes nothing")
  func stability() throws {
    let samples: [Expr] = [
      x + y + 1, Expr.integer(2) * x * y, (try x.raised(to: 2)) + Expr.integer(3) * x + 2, (try x.divided(by: y)),
      Expr.fraction(1, 3) * .pi, (try Expr.integer(2).raised(to: half)) + (try Expr.integer(3).raised(to: half)),
      (try Expr.apply(.sin, [x])) * (try Expr.apply(.cos, [y])), (try Expr.integer(1).divided(by: x + 1)),
      (try Expr.e.raised(to: x + 1)), Expr.integer(-3) * x - y, (try Expr.apply(.ln, [x])) + .pi,
    ]
    for sample in samples {
      #expect(try sample.rebuilt() == sample, "\(sample)")
    }
  }

  @Test("Functions have exact values at the usual points and keep their symmetries")
  func functions() throws {
    #expect(try Expr.apply(.sin, [.zero]) == .zero)
    #expect(try Expr.apply(.cos, [.zero]) == .one)
    #expect(try Expr.apply(.sin, [-x]) == -(try Expr.apply(.sin, [x])))
    #expect(try Expr.apply(.cos, [-x]) == (try Expr.apply(.cos, [x])))
    #expect(try Expr.apply(.tan, [-x]) == -(try Expr.apply(.tan, [x])))
    #expect(try Expr.apply(.abs, [-x]) == (try Expr.apply(.abs, [x])))
    #expect(try Expr.apply(.abs, [Expr.integer(-3) * x]) == Expr.integer(3) * (try Expr.apply(.abs, [x])))
    #expect(try Expr.apply(.abs, [.pi]) == .pi)
    #expect(try Expr.apply(.ln, [.e]) == .one)
    #expect(try Expr.apply(.sinh, [.zero]) == .zero)
    #expect(try Expr.apply(.cosh, [.zero]) == .one)
    #expect(try Expr.apply(.acosh, [.one]) == .zero)
    #expect(try Expr.apply(.factorial, [x]) == .function(.factorial, [x]))
    #expect(throws: MathError.domain) { try Expr.apply(.atanh, [.one]) }
    #expect(throws: MathError.domain) { try Expr.apply(.acosh, [half]) }
    #expect(throws: MathError.domain) { try Expr.apply(.log, [4, 1]) }
    #expect(throws: MathError.domain) { try Expr.apply(.log, [-4, 2]) }
    #expect(throws: MathError.overflow) { try Expr.apply(.factorial, [1_000_000]) }
  }

  @Test("Approximations of exact expressions")
  func approximations() throws {
    let root = try Expr.integer(2).raised(to: half)
    #expect(try root.approximation(precision: 30) == BigDecimal("1.41421356237309504880168872421"))
    #expect(try (root * root).approximation() == BigDecimal(2))
    #expect(try Expr.fraction(1, 3).approximation(precision: 5) == BigDecimal("0.33333"))
    #expect(try (x + 1).approximation(values: ["x": BigDecimal("2.5")!]) == BigDecimal("3.5"))
    #expect(throws: MathError.notNumeric) { try (x + 1).approximation() }
    #expect(throws: MathError.domain) { try Expr.integer(-4).raised(to: half).approximation() }
    #expect(try Expr.integer(-8).raised(to: Expr.fraction(1, 3)).approximation() == BigDecimal(-2))
    // Huge arguments need extra digits internally: cos of a 38-digit angle is still right to the digits asked for.
    let angle = Expr.pi * (try Expr.e.raised(to: 90)) * Expr.fraction(1, 180)
    let cosine = try Expr.apply(.cos, [angle])
    #expect(try cosine.approximation(precision: 30) == BigDecimal("0.354232625401768305449396433387"))
    // tan of a 98-digit angle (checked against Python at 300 digits).
    let huge = Expr.pi * (try Expr.e.raised(to: 232)) * Expr.fraction(1, 180)
    #expect(
      try Expr.apply(.tan, [huge]).approximation(precision: 40)
        == BigDecimal("0.2469891127822497174158862923241675331468"))
  }
}

extension Expr {
  /// `self^exponent` for tests that do not care about error cases.
  fileprivate func raised(toUnchecked exponent: Expr) -> Expr { try! raised(to: exponent) }
}
