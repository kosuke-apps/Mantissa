import Testing

@testable import MantissaCore

@Suite("Parser")
struct ParserTests {
  private let x = Syntax.symbol("x")
  private let y = Syntax.symbol("y")
  private func n(_ value: Int) -> Syntax { .number(Rational(value)) }

  private func parse(_ text: String) throws -> Syntax {
    guard case .expression(let syntax) = try Parser.parse(text) else {
      Issue.record("\(text) did not parse as a plain expression")
      return .number(Rational(0))
    }
    return syntax
  }

  private func error(_ text: String) -> ParseError? {
    do {
      _ = try Parser.parse(text)
      return nil
    } catch {
      return error
    }
  }

  @Test("Operators bind in the usual order")
  func precedence() throws {
    #expect(try parse("1+2*3") == .binary(.add, n(1), .binary(.multiply, n(2), n(3))))
    #expect(try parse("(1+2)*3") == .binary(.multiply, .binary(.add, n(1), n(2)), n(3)))
    #expect(try parse("6/3/2") == .binary(.divide, .binary(.divide, n(6), n(3)), n(2)))
    #expect(try parse("1-2-3") == .binary(.subtract, .binary(.subtract, n(1), n(2)), n(3)))
    #expect(try parse("2^3^2") == .binary(.power, n(2), .binary(.power, n(3), n(2))))
    #expect(try parse("-x^2") == .negate(.binary(.power, x, n(2))))
    #expect(try parse("2^-3") == .binary(.power, n(2), .negate(n(3))))
    #expect(try parse("2*-3") == .binary(.multiply, n(2), .negate(n(3))))
    #expect(try parse("--x") == .negate(.negate(x)))
    #expect(try parse("+x") == x)
    #expect(try parse("x^2y") == .binary(.multiply, .binary(.power, x, n(2)), y))
  }

  @Test("Juxtaposition is multiplication at the level of * and /")
  func implicitMultiplication() throws {
    #expect(try parse("2x") == .binary(.multiply, n(2), x))
    #expect(try parse("2x^2") == .binary(.multiply, n(2), .binary(.power, x, n(2))))
    #expect(try parse("xy") == .binary(.multiply, x, y))
    #expect(try parse("1/2x") == .binary(.multiply, .binary(.divide, n(1), n(2)), x))
    #expect(try parse("2(x+1)") == .binary(.multiply, n(2), .binary(.add, x, n(1))))
    #expect(try parse("(x+1)(x-1)") == .binary(.multiply, .binary(.add, x, n(1)), .binary(.subtract, x, n(1))))
    #expect(try parse("2π") == .binary(.multiply, n(2), .constant(.pi)))
    #expect(try parse("3e") == .binary(.multiply, n(3), .constant(.e)))
    #expect(try parse("xyz") == .binary(.multiply, .binary(.multiply, x, y), .symbol("z")))
    #expect(try parse("2 x") == .binary(.multiply, n(2), x))
    #expect(try parse("pie") == .binary(.multiply, .constant(.pi), .constant(.e)))
  }

  @Test("Functions take parentheses, or one tight operand without them")
  func functionCalls() throws {
    #expect(try parse("sin(x)") == .call(.sin, [x]))
    #expect(try parse("sinx") == .call(.sin, [x]))
    #expect(try parse("sin x") == .call(.sin, [x]))
    #expect(try parse("sin x^2") == .call(.sin, [.binary(.power, x, n(2))]))
    #expect(try parse("sin 2x") == .binary(.multiply, .call(.sin, [n(2)]), x))
    #expect(try parse("sin(x)^2") == .binary(.power, .call(.sin, [x]), n(2)))
    #expect(try parse("sin(x)cos(x)") == .binary(.multiply, .call(.sin, [x]), .call(.cos, [x])))
    #expect(try parse("log(8, 2)") == .call(.log, [n(8), n(2)]))
    #expect(try parse("log(8)") == .call(.log, [n(8)]))
    #expect(try parse("nCr(5,2)") == .call(.nCr, [n(5), n(2)]))
    #expect(try parse("arcsin(x)") == .call(.asin, [x]))
    #expect(try parse("arctan x") == .call(.atan, [x]))
    #expect(try parse("ln x + 1") == .binary(.add, .call(.ln, [x]), n(1)))
    #expect(try parse("sin -x") == .call(.sin, [.negate(x)]))
  }

  @Test("Radicals take the next primary only")
  func radicals() throws {
    #expect(try parse("√2") == .radical(index: nil, radicand: n(2)))
    #expect(try parse("√2x") == .binary(.multiply, .radical(index: nil, radicand: n(2)), x))
    #expect(try parse("√x^2") == .binary(.power, .radical(index: nil, radicand: x), n(2)))
    #expect(try parse("√(x+1)") == .radical(index: nil, radicand: .binary(.add, x, n(1))))
    #expect(try parse("√√2") == .radical(index: nil, radicand: .radical(index: nil, radicand: n(2))))
    #expect(try parse("∛8") == .radical(index: n(3), radicand: n(8)))
    #expect(try parse("√-4") == .radical(index: nil, radicand: .negate(n(4))))
    #expect(try parse("sqrt(2)") == .call(.sqrt, [n(2)]))
    #expect(try parse("root(8,3)") == .call(.root, [n(8), n(3)]))
  }

  @Test("Postfix operators: factorial, percent, degrees")
  func postfix() throws {
    #expect(try parse("5!") == .postfix(.factorial, n(5)))
    #expect(try parse("-3!") == .negate(.postfix(.factorial, n(3))))
    #expect(try parse("n!^2") == .binary(.power, .postfix(.factorial, .symbol("n")), n(2)))
    #expect(try parse("(n+1)!") == .postfix(.factorial, .binary(.add, .symbol("n"), n(1))))
    #expect(try parse("3!!") == .postfix(.factorial, .postfix(.factorial, n(3))))
    #expect(try parse("50%") == .postfix(.percent, n(50)))
    #expect(try parse("30°") == .postfix(.degree, n(30)))
    #expect(try parse("200+10%") == .binary(.add, n(200), .postfix(.percent, n(10))))
  }

  @Test("Absolute value bars")
  func bars() throws {
    #expect(try parse("|x|") == .call(.abs, [x]))
    #expect(try parse("|x||y|") == .binary(.multiply, .call(.abs, [x]), .call(.abs, [y])))
    #expect(try parse("2|x-1|") == .binary(.multiply, n(2), .call(.abs, [.binary(.subtract, x, n(1))])))
    #expect(try parse("|-5|") == .call(.abs, [.negate(n(5))]))
  }

  @Test("Numbers: decimals, exponents, superscripts, fullwidth digits")
  func numbers() throws {
    #expect(try parse("1.5") == .number(Rational(3, 2)))
    #expect(try parse(".5") == .number(Rational(1, 2)))
    #expect(try parse("5.") == n(5))
    #expect(try parse("1.5E3") == n(1500))
    #expect(try parse("2E-2") == .number(Rational(1, 50)))
    #expect(try parse("1E+2") == n(100))
    #expect(try parse("2e3") == .binary(.multiply, .binary(.multiply, n(2), .constant(.e)), n(3)))
    #expect(try parse("x²") == .binary(.power, x, n(2)))
    #expect(try parse("x¹⁰") == .binary(.power, x, n(10)))
    #expect(try parse("x⁻¹") == .binary(.power, x, .negate(n(1))))
    #expect(try parse("１２３") == n(123))
    #expect(try parse("３．５") == .number(Rational(7, 2)))
    #expect(try parse("0.1+0.2") == .binary(.add, .number(Rational(1, 10)), .number(Rational(1, 5))))
  }

  @Test("Equations, inequalities, chains and systems")
  func relations() throws {
    func chain(_ text: String) throws -> RelationChain {
      guard case .relation(let chain) = try Parser.parse(text) else {
        Issue.record("\(text) is not a relation")
        return RelationChain(first: x, links: [])
      }
      return chain
    }
    #expect(try chain("x=3") == RelationChain(first: x, links: [(.equal, n(3))]))
    #expect(try chain("x==3") == RelationChain(first: x, links: [(.equal, n(3))]))
    #expect(try chain("x≠2") == RelationChain(first: x, links: [(.notEqual, n(2))]))
    #expect(try chain("x != 2") == RelationChain(first: x, links: [(.notEqual, n(2))]))
    #expect(try chain("x<=3") == RelationChain(first: x, links: [(.lessOrEqual, n(3))]))
    #expect(try chain("x≥3") == RelationChain(first: x, links: [(.greaterOrEqual, n(3))]))
    #expect(try chain("1<x≤5") == RelationChain(first: n(1), links: [(.less, x), (.lessOrEqual, n(5))]))
    #expect(
      try chain("2x+1=x-4")
        == RelationChain(
          first: .binary(.add, .binary(.multiply, n(2), x), n(1)), links: [(.equal, .binary(.subtract, x, n(4)))]))

    guard case .system(let parts) = try Parser.parse("x+y=3, x-y=1") else {
      Issue.record("not a system")
      return
    }
    #expect(parts.count == 2)
    guard case .system(let lines) = try Parser.parse("x=1\ny=2\n") else {
      Issue.record("line breaks do not separate a system")
      return
    }
    #expect(lines.count == 2)
    guard case .system(let semicolons) = try Parser.parse("a=1; b=2") else {
      Issue.record("semicolons do not separate a system")
      return
    }
    #expect(semicolons.count == 2)
  }

  @Test("Errors point at the offending character")
  func errors() {
    #expect(error(")") == ParseError(reason: .unexpectedToken(")"), offset: 0))
    #expect(error("1+*") == ParseError(reason: .unexpectedToken("×"), offset: 2))
    #expect(error("1+") == ParseError(reason: .unexpectedEnd, offset: 2))
    #expect(error("(1+2") == ParseError(reason: .missingClosingParenthesis, offset: 4))
    #expect(error("1+2)") == ParseError(reason: .unexpectedToken(")"), offset: 3))
    #expect(error("sin") == ParseError(reason: .unexpectedEnd, offset: 3))
    #expect(error("sin()") == ParseError(reason: .wrongArgumentCount(function: "sin", expected: "1"), offset: 0))
    #expect(error("1.2.3") == ParseError(reason: .unexpectedToken("0.3"), offset: 3))
    #expect(error("2 3") == ParseError(reason: .unexpectedToken("3"), offset: 2))
    #expect(error("x $ y") == ParseError(reason: .unexpectedCharacter("$"), offset: 2))
    #expect(error("x = ") == ParseError(reason: .unexpectedEnd, offset: 4))
    #expect(error("  ") == ParseError(reason: .empty, offset: 0))
    #expect(error("^2") == ParseError(reason: .unexpectedToken("^"), offset: 0))
    #expect(error("sin(1,2)") == ParseError(reason: .wrongArgumentCount(function: "sin", expected: "1"), offset: 0))
  }
}
