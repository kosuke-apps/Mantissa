import Foundation
import Testing

@testable import MantissaCore

/// The factored form (or the simplified one) of an expression, as it is read.
private func factoredText(_ text: String) throws -> String? {
  for form in try Calculator().evaluate(text).otherForms {
    if case .factored(let factorization) = form { return Typesetter.nodes(for: factorization).plainText }
  }
  return nil
}

private func polynomial(_ text: String, names: [String]) throws -> MultiPolynomial {
  let expression = try Calculator().evaluate(text).exact
  return try #require(MultiPolynomial(expression, ring: PolynomialRing(names: names, budget: 1_000_000)))
}

@Suite("Factoring in several unknowns")
struct MultivariateFactoringTests {
  @Test(
    "Textbook factorizations",
    arguments: [
      ("a^2-b^2", "(a − b)(a + b)"), ("a^2+2ab+b^2", "(a + b)^2"), ("a^2-2ab+b^2", "(a − b)^2"),
      ("a^3-b^3", "(a − b)(a^2 + ab + b^2)"), ("a^3+b^3", "(a + b)(a^2 − ab + b^2)"),
      ("x^2+xy-2y^2", "(x − y)(x + 2y)"), ("6x^2+5xy-6y^2", "(2x + 3y)(3x − 2y)"),
      ("ax+ay+bx+by", "(a + b)(x + y)"), ("x^2-y^2+x+y", "(x + y)(x − y + 1)"),
      ("a^2-4b^2+a+2b", "(a + 2b)(a − 2b + 1)"), ("x^2+2xy+y^2-z^2", "(x + y − z)(x + y + z)"),
      ("x^4-y^4", "(x − y)(x + y)(x^2 + y^2)"), ("x^3+x^2y-xy^2-y^3", "(x − y)(x + y)^2"),
      ("x^4+4y^4", "(x^2 − 2xy + 2y^2)(x^2 + 2xy + 2y^2)"),
      ("x^4+x^2y^2+y^4", "(x^2 − xy + y^2)(x^2 + xy + y^2)"), ("2x^2y-8y", "2y(x − 2)(x + 2)"),
      ("(a+b)^2-(a-b)^2", "4ab"),
    ])
  func polynomials(input: String, expected: String) throws {
    #expect(try factoredText(input) == expected)
  }

  @Test(
    "Fractions in several unknowns are cancelled",
    arguments: [
      ("(a^2-b^2)/(a-b)", "a + b"), ("(x^3-y^3)/(x-y)", "x^2 + xy + y^2"),
      ("(x^2-y^2)/(x^2+2xy+y^2)", "(x − y)/(x + y)"), ("(x^2+xy)/(xy+y^2)", "x/y"), ("(a^2-b^2)/(b-a)", "−(a + b)"),
      ("(a^2-b^2)/(a^2+2ab+b^2)", "(a − b)/(a + b)"),
    ])
  func cancelling(input: String, expected: String) throws {
    #expect(try factoredText(input) == expected)
  }

  @Test(
    "Everyday factorizations use a small part of the work budget",
    arguments: [
      "a^2-b^2", "a^3-b^3", "x^2+xy-2y^2", "6x^2+5xy-6y^2", "ax+ay+bx+by", "x^2-y^2+x+y", "x^2+2xy+y^2-z^2", "x^4-y^4",
      "x^3+x^2y-xy^2-y^3", "x^4+4y^4", "x^4+x^2y^2+y^4", "2x^2y-8y",
    ])
  func workIsSmall(input: String) throws {
    let ring = PolynomialRing(
      names: ["x", "y", "z", "a", "b"].filter { input.contains($0) }.sorted(), budget: 1_000_000)
    let source = try #require(MultiPolynomial(try Calculator().evaluate(input).exact, ring: ring))
    _ = source.factored()
    #expect(ring.spent < 5_000, "\(input) used \(ring.spent)")
  }

  @Test("A cancelled fraction is labelled as simplified")
  func simplifiedLabel() throws {
    let forms = try Calculator().evaluate("(a^2-b^2)/(a-b)").otherForms
    let cancelled = forms.compactMap { form -> Bool? in
      if case .factored(let factorization) = form { return factorization.cancelled }
      return nil
    }
    #expect(cancelled == [true])
  }

  @Test("Univariate factors of higher degree: x⁴ + 4, x⁶ − 1, x⁸ − 1")
  func higherDegreeFactors() throws {
    #expect(try factoredText("x^4+4") == "(x^2 − 2x + 2)(x^2 + 2x + 2)")
    #expect(try factoredText("x^4+x^2+1") == "(x^2 − x + 1)(x^2 + x + 1)")
    #expect(try factoredText("x^6-1") == "(x + 1)(x − 1)(x^2 − x + 1)(x^2 + x + 1)")
    #expect(try factoredText("x^8-1") == "(x + 1)(x − 1)(x^2 + 1)(x^4 + 1)")
  }

  @Test("Irreducible polynomials are left whole")
  func irreducible() throws {
    #expect(try factoredText("x^2+y^2") == nil)
    #expect(try factoredText("x^2+x+1") == nil)
    #expect(try factoredText("x^2y+1") == nil)
  }

  @Test("A sum of fractions is read as one fraction")
  func sumsOfFractions() throws {
    #expect(try factoredText("1/x-1/y") == "(y − x)/(xy)")
    #expect(try factoredText("1/(x+y)+1/(x-y)") == "2x/((x − y)(x + y))")
  }
}

@Suite("Polynomial arithmetic in several unknowns")
struct MultiPolynomialPropertyTests {
  private static let names = ["a", "b", "c"]

  private static func makeRing(budget: Int = Int.max / 2) -> PolynomialRing {
    PolynomialRing(names: names, budget: budget)
  }

  /// A random polynomial with a few terms, each unknown to a power of at most two.
  private static func randomPolynomial(
    in ring: PolynomialRing, using generator: inout SplitMix64, terms: Int = 3
  ) -> MultiPolynomial {
    var result = MultiPolynomial(ring: ring)
    for _ in 0..<terms {
      let monomial = ring.names.map { _ in Int(generator.next() % 3) }
      var coefficient = Int(generator.next() % 7) - 3
      if coefficient == 0 { coefficient = 1 }
      result = result + MultiPolynomial(ring: ring, terms: [monomial: Rational(coefficient)])
    }
    return result
  }

  @Test("The factors of a product multiply back to it, and a hard one is given up on rather than waited for")
  func factoringIsSound() {
    var generator = SplitMix64(seed: 2024 &+ propertySeedOffset)
    var gaveUp = 0
    var checked = 0
    for _ in 0..<60 {
      let ring = Self.makeRing(budget: Factoring.workBudget)
      var product = MultiPolynomial.constant(Rational(1), ring: ring)
      for _ in 0..<(2 + Int(generator.next() % 2)) {
        product = product * Self.randomPolynomial(in: ring, using: &generator, terms: 2)
      }
      guard !product.isZero else { continue }
      let (coefficient, factors) = product.factored()
      if ring.isExhausted {
        gaveUp += 1
        continue
      }
      checked += 1
      // Compare outside the budget: the check itself is not what is being limited.
      let checking = Self.makeRing()
      func moved(_ polynomial: MultiPolynomial) -> MultiPolynomial {
        MultiPolynomial(ring: checking, terms: polynomial.terms)
      }
      var rebuilt = MultiPolynomial.constant(coefficient, ring: checking)
      for (base, power) in factors {
        #expect(!base.isConstant, "a constant listed as a factor of \(product.expression)")
        #expect(base == base.normalized, "factor \(base.expression) is not normalized")
        rebuilt = rebuilt * moved(base).power(power)
      }
      #expect(
        rebuilt == moved(product), "\(product.expression) factored as \(coefficient) \(factors.map(\.base.expression))")
    }
    #expect(checked >= 30, "only \(checked) were factored in the budget; \(gaveUp) were given up on")
  }

  @Test("The greatest common divisor is divisible by the common factor and divides both")
  func gcdProperties() {
    var generator = SplitMix64(seed: 99 &+ propertySeedOffset)
    var checked = 0
    for _ in 0..<60 {
      let ring = Self.makeRing(budget: Factoring.workBudget)
      let common = Self.randomPolynomial(in: ring, using: &generator, terms: 2)
      let first = Self.randomPolynomial(in: ring, using: &generator, terms: 2) * common
      let second = Self.randomPolynomial(in: ring, using: &generator, terms: 2) * common
      guard !common.isZero, !first.isZero, !second.isZero else { continue }
      let divisor = MultiPolynomial.gcd(first, second)
      if ring.isExhausted { continue }
      checked += 1
      #expect(first.dividedExactly(by: divisor) != nil, "\(divisor.expression) does not divide \(first.expression)")
      #expect(second.dividedExactly(by: divisor) != nil, "\(divisor.expression) does not divide \(second.expression)")
      #expect(divisor.dividedExactly(by: common.normalized) != nil, "\(common.expression) is not in the gcd")
    }
    #expect(checked >= 40, "only \(checked) were checked")
  }

  @Test("The square root of a square is found")
  func squareRoots() {
    var generator = SplitMix64(seed: 7 &+ propertySeedOffset)
    for _ in 0..<60 {
      let root = Self.randomPolynomial(in: Self.makeRing(), using: &generator, terms: 3)
      guard !root.isZero else { continue }
      let found = (root * root).exactSquareRoot()
      #expect(found == root || found == -root, "\(root.expression)")
    }
    #expect((try! polynomial("x^2+1", names: ["x"])).exactSquareRoot() == nil)
  }

  @Test("Repeated factors are separated: x²(x + 1)³(y − 1)")
  func repeatedFactors() throws {
    let source = try polynomial("x^2*(x+1)^3*(y-1)", names: ["x", "y"])
    let (coefficient, factors) = source.squarefreeDecomposition()
    #expect(coefficient == Rational(1))
    #expect(factors.count == 3)
    let powers = Dictionary(uniqueKeysWithValues: factors.map { ($0.base.expression.description, $0.power) })
    #expect(powers["x"] == 2)
    #expect(powers["x + 1"] == 3)
    #expect(powers["y - 1"] == 1)
  }
}

@Suite("Roots of squares")
struct SquareRootSimplificationTests {
  @Test(
    "Square roots of perfect squares and their repeated parts",
    arguments: [
      ("sqrt(x^2+2x+1)", "|x + 1|"), ("sqrt(4x^2+12x+9)", "|2x + 3|"), ("sqrt(a^2b)", "|a|√b"),
      ("sqrt(2x^2+4x+2)", "|x + 1|√2"), ("sqrt(a^2+2ab+b^2)", "|a + b|"), ("sqrt(x^2y^2)", "|x||y|"),
      ("1/sqrt(x^2-2x+1)", "1/|x − 1|"), ("sqrt(x^2+y^2)", "√(x^2 + y^2)"),
    ])
  func roots(input: String, expected: String) throws {
    #expect(Typesetter.nodes(for: try Calculator().evaluate(input).exact).plainText == expected)
  }

  @Test("The simplified root has the value of the original")
  func sameValue() throws {
    let cases: [(String, String)] = [
      ("sqrt(x^2+2x+1)", "abs(x+1)"), ("sqrt(x^3+2x^2+x)", "sqrt(x)*abs(x+1)"),
      ("(x^2-6x+9)^(3/2)", "abs(x-3)^3"), ("sqrt(9x^2*y)", "3*abs(x)*sqrt(y)"),
    ]
    for (input, reference) in cases {
      let simplified = try Calculator().evaluate(input).exact
      let expected = try Calculator().evaluate(reference).exact
      for point in [Rational(13, 10), Rational(5, 2), Rational(7)] {
        let values = ["x": BigDecimal(point, precision: 40), "y": BigDecimal(point + Rational(1, 3), precision: 40)]
        let a = try simplified.approximation(precision: 40, values: values)
        let b = try expected.approximation(precision: 40, values: values)
        #expect((a - b).magnitude < BigDecimal(BigInt(1), exponent: -30), "\(input) at \(point)")
      }
    }
  }
}

@Suite("What the terms of a sum have in common")
struct CommonFactorTests {
  @Test(
    "The common factor comes out",
    arguments: [
      ("x*e^x-e^x", "e^x·(x − 1)"), ("x*ln(x)-x", "x(ln(x) − 1)"), ("x*sin(x)+sin(x)", "sin(x)(x + 1)"),
      ("2x*e^x+4e^x", "2e^x·(x + 2)"), ("-x*e^x-e^x", "−e^x·(x + 1)"), ("x^(3/2)-x^(1/2)", "√x·(x − 1)"),
      ("ln(x)/2-ln(x+1)/2", "(ln(x) − ln(x + 1))/2"), ("x^3*ln(x)+x^2", "x^2·(x ln(x) + 1)"),
    ])
  func common(input: String, expected: String) throws {
    let text = try #require(try factoredText(input), "\(input) has no factored form")
    // Compare ignoring the spaces the typesetter puts around some signs.
    #expect(text.replacingOccurrences(of: " ", with: "") == expected.replacingOccurrences(of: " ", with: ""))
  }

  @Test("The factored form has the value of the sum")
  func sameValue() throws {
    for input in ["x*e^x-e^x", "x^(3/2)-x^(1/2)", "2x*e^x+4e^x", "x*ln(x)-x", "ln(x)/2-ln(x+1)/2", "-x*e^x-e^x"] {
      let evaluation = try Calculator().evaluate(input)
      guard
        case .factored(let factorization)? = evaluation.otherForms.first(where: {
          if case .factored = $0 { return true } else { return false }
        })
      else {
        Issue.record("\(input) has no factored form")
        continue
      }
      for point in [Rational(13, 10), Rational(5, 2), Rational(7)] {
        let values = ["x": BigDecimal(point, precision: 40)]
        let a = try evaluation.exact.approximation(precision: 40, values: values)
        let b = try factorization.expression.approximation(precision: 40, values: values)
        #expect((a - b).magnitude < BigDecimal(BigInt(1), exponent: -30), "\(input) at \(point)")
      }
    }
  }

  @Test("No common factor, no form")
  func none() throws {
    #expect(try factoredText("x+sin(x)") == nil)
    #expect(try factoredText("e^x+x") == nil)
    #expect(try factoredText("sin(x)+cos(x)") == nil)
  }
}
