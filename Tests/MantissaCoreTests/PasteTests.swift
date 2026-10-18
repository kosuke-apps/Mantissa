import Testing

@testable import MantissaCore

/// Text laid out as editor nodes, for pasting. A formula that goes into nodes and comes out as text must mean what it did.
@Suite("Pasting a formula")
struct PasteTests {
  private func text(_ source: String) -> String? {
    MathEditor.lines(fromText: source).map { MathEditor(lines: $0).text }
  }

  @Test(
    "A formula becomes nodes that read back as the same formula",
    arguments: [
      ("2x^2+sqrt(3)", "2x^(2)+√(3)"), ("1/3", "((1)/(3))"), ("x^2+y^2=25", "x^(2)+y^(2)=25"),
      ("0.25", "0.25"), ("-(a+b)", "−(a+b)"), ("a-(b-c)", "a−(b−c)"), ("a+-b", "a−b"), ("x*y", "x*y"),
      ("2*3", "2×3"), ("2(3+4)", "2(3+4)"), ("sin(x)cos(x)", "sin(x)cos(x)"), ("(a+b)^2", "(a+b)^(2)"),
      ("(a^b)^c", "(a^(b))^(c)"), ("a^b^c", "a^(b^(c))"), ("5!", "5!"), ("(x^2)!", "(x^(2))!"), ("x<=3", "x≤3"),
      ("1<x<5", "1<x<5"), ("|x-1|", "abs(x−1)"), ("log(8,2)", "log(8,2)"), ("log(100)", "log(100)"),
      ("root(8,3)", "root(8,3)"), ("cbrt(8)", "root(8,3)"), ("2e^x", "2e^(x)"), ("1/2/3", "((((1)/(2)))/(3))"),
      ("x%", "x%"), ("30°", "30°"), ("∞", "∞"), ("π", "π"), ("-3^2", "−3^(2)"), ("2^-1", "2^(−1)"),
      ("arcsin(x)", "asin(x)"), ("1.5E3", "1500"),
    ])
  func layout(source: String, expected: String) {
    #expect(text(source) == expected, "\(source)")
  }

  @Test("Calculus in boxes")
  func calculus() {
    #expect(text("int(x^2,x)") == "int(x^(2),x)")
    #expect(text("int(x^2,x,0,1)") == "int(x^(2),x,0,1)")
    #expect(text("sum(1/k^2,k,1,∞)") == "sum(((1)/(k^(2))),k,1,∞)")
    #expect(text("lim(sin(x)/x,x,0)") == "lim(((sin(x))/(x)),x,0)")
    #expect(text("lim(1/x,x,0,1)") == "lim(((1)/(x)),x,0,1)")
    #expect(text("lim(1/x,x,0,-1)") == "lim(((1)/(x)),x,0,-1)")
    #expect(text("diff(x^3)") == "diff(x^(3),x)")
    #expect(text("diff(x^3,x)") == "diff(x^(3),x)")
    let integral = MathEditor.lines(fromText: "int(x^2,x,0,1)")?.first
    guard case .calculus(.integral, let slots)? = integral?.first else {
      Issue.record("not a calculus node")
      return
    }
    #expect(slots.count == 4 && slots[1] == [.symbol("x")] && slots[2] == [.symbol("0")] && slots[3] == [.symbol("1")])
    // A one-sided limit has its small mark in the point box.
    guard case .calculus(.limit, let limit)? = MathEditor.lines(fromText: "lim(1/x,x,0,1)")?.first?.first else {
      Issue.record("not a limit")
      return
    }
    #expect(limit[2] == [.symbol("0"), .symbol("⁺")])
  }

  @Test("A system is one line per equation, and what is not a formula is refused")
  func systemsAndErrors() {
    #expect(MathEditor.lines(fromText: "x+y=5\nx-y=1")?.count == 2)
    #expect(MathEditor.lines(fromText: "x+y=5, x-y=1")?.count == 2)
    for bad in ["", "2+", "(1", "sin(", "x=", "2 3", "1/", "%%"] {
      #expect(MathEditor.lines(fromText: bad) == nil, "\(bad)")
    }
  }

  @Test("Pasting puts the formula at the cursor, and a system continues on new lines")
  func pasting() throws {
    var editor = MathEditor()
    editor.insert("5")
    editor.insert("+")
    let pasted = editor.paste("2x")
    #expect(pasted)
    #expect(editor.text == "5+2x")
    #expect(editor.isValid)
    editor.insert("+")
    editor.insert("1")
    #expect(editor.text == "5+2x+1")

    var system = MathEditor()
    let systemPasted = system.paste("x+y=5\nx-y=1")
    #expect(systemPasted)
    #expect(system.lines.count == 2 && system.isValid)
    #expect(system.text == "x+y=5\nx−y=1")

    var unchanged = MathEditor()
    unchanged.insert("7")
    let refused = unchanged.paste("2+")
    #expect(!refused)
    #expect(unchanged.text == "7")
  }

  @Test("Numbers that do not end become fractions, and decimals keep their digits")
  func numbers() throws {
    #expect(text("0.125") == "0.125")
    #expect(text("100.5") == "100.5")
    #expect(text("0.001") == "0.001")
    let third = SyntaxLayout.lines(for: .expression(.number(Rational(1, 3))))
    #expect(MathEditor(lines: third).text == "((1)/(3))")
    let negative = SyntaxLayout.lines(for: .expression(.number(Rational(-5, 4))))
    #expect(MathEditor(lines: negative).text == "−1.25")
  }

  @Test("Random formulas keep their value through nodes and text", arguments: [AngleUnit.radians, AngleUnit.degrees])
  func randomRoundTrip(angleUnit: AngleUnit) throws {
    var generator = SyntaxGenerator(seed: (angleUnit == .radians ? 8128 : 496) &+ propertySeedOffset &* 7919)
    generator.includesDerivedFunctions = true
    generator.includesUnknown = true
    let builder = Builder(angleUnit: angleUnit)
    var compared = 0
    var failures: [String] = []
    for _ in 0..<350 {
      let syntax = generator.make(depth: 4)
      guard let original = try? builder.build(syntax) else { continue }
      let lines = SyntaxLayout.lines(for: .expression(syntax))
      let written = MathEditor(lines: lines).text
      guard case .expression(let reparsed)? = try? Parser.parse(written) else {
        failures.append("did not parse: \(written)")
        continue
      }
      guard let again = try? builder.build(reparsed) else {
        failures.append("did not build: \(written)")
        continue
      }
      compared += 1
      // The same value. (The canonical form of a product with a sum in it can differ in shape, −(a − b)c against (b − a)c,
      // so the expressions are compared by value at two points.)
      for point in [BigDecimal(BigInt(13), exponent: -1), BigDecimal(BigInt(-7), exponent: -1)] {
        let values = ["x": point]
        let a = try? original.approximation(precision: 40, values: values)
        let b = try? again.approximation(precision: 40, values: values)
        switch (a, b) {
        case (let a?, let b?):
          let scale = max(BigDecimal(1), a.magnitude)
          if (a - b).magnitude > scale * BigDecimal(BigInt(1), exponent: -30) {
            failures.append("\(written): \(a) became \(b)")
          }
        case (nil, nil): break
        default: failures.append("\(written): \(String(describing: a)) became \(String(describing: b))")
        }
      }
    }
    #expect(compared > 120, "only \(compared) compared")
    #expect(failures.isEmpty, "\(failures.count) failures; first: \(failures.prefix(4))")
  }
}
