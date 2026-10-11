import Foundation
import Testing

@testable import MantissaCore

extension MathEditor {
  /// Presses the keys for each character of `text`.
  mutating func type(_ text: String) {
    for character in text { insert(String(character)) }
  }

  /// Every cursor position reachable by moving right from the very start.
  fileprivate func positionsGoingRight() -> [MathCursor] {
    var editor = self
    for _ in 0..<10_000 {  // go to the start
      let before = editor.cursor
      editor.moveLeft()
      if editor.cursor == before { break }
    }
    var positions = [editor.cursor]
    for _ in 0..<10_000 {
      let before = editor.cursor
      editor.moveRight()
      if editor.cursor == before { break }
      positions.append(editor.cursor)
    }
    return positions
  }

  /// Every cursor position reachable by moving left from the very end.
  fileprivate func positionsGoingLeft() -> [MathCursor] {
    var editor = self
    for _ in 0..<10_000 {
      let before = editor.cursor
      editor.moveRight()
      if editor.cursor == before { break }
    }
    var positions = [editor.cursor]
    for _ in 0..<10_000 {
      let before = editor.cursor
      editor.moveLeft()
      if editor.cursor == before { break }
      positions.append(editor.cursor)
    }
    return positions
  }
}

private func evaluate(_ editor: MathEditor, unit: AngleUnit = .radians) throws -> String {
  var settings = CalculatorSettings()
  settings.angleUnit = unit
  return try Calculator(settings: settings).evaluate(editor.text).exact.description
}

@Suite("Math editor")
struct MathEditorTests {
  @Test("Typing characters")
  func typing() throws {
    var editor = MathEditor()
    #expect(editor.isEmpty)
    editor.type("12+3")
    #expect(editor.text == "12+3")
    #expect(!editor.isEmpty)
    #expect(try evaluate(editor) == "15")
    editor.clear()
    #expect(editor.isEmpty && editor.text.isEmpty)
  }

  @Test("A fraction takes the number before it as its numerator and leaves the cursor in the denominator")
  func fractionOfANumber() throws {
    var editor = MathEditor()
    editor.type("12")
    editor.insertFraction()
    editor.type("5")
    #expect(editor.lines == [[.fraction(numerator: [.symbol("1"), .symbol("2")], denominator: [.symbol("5")])]])
    #expect(editor.text == "((12)/(5))")
    editor.moveRight()  // out of the denominator
    editor.type("+1")
    #expect(editor.text == "((12)/(5))+1")
    #expect(try evaluate(editor) == "17/5")
  }

  @Test("A fraction with nothing before it starts in an empty numerator")
  func emptyFraction() throws {
    var editor = MathEditor()
    editor.insertFraction()
    editor.type("1")
    editor.moveRight()
    editor.type("2")
    #expect(editor.text == "((1)/(2))")
    #expect(try evaluate(editor) == "1/2")

    var incomplete = MathEditor()
    incomplete.insertFraction()
    #expect(throws: ParseError.self) { try Parser.parse(incomplete.text) }
  }

  @Test("What a fraction takes: a variable with its exponent, a group, a function; not an operator")
  func fractionOperands() throws {
    var power = MathEditor()
    power.type("x")
    power.insertPower()
    power.type("2")
    power.moveRight()
    power.insertFraction()
    #expect(power.lines == [[.fraction(numerator: [.symbol("x"), .superscript([.symbol("2")])], denominator: [])]])

    var group = MathEditor()
    group.type("(1+2)")
    group.insertFraction()
    #expect(
      group.lines == [[.fraction(numerator: [.group([.symbol("1"), .symbol("+"), .symbol("2")])], denominator: [])]])

    var afterOperator = MathEditor()
    afterOperator.type("3+")
    afterOperator.insertFraction()
    #expect(
      afterOperator.lines == [[.symbol("3"), .symbol("+"), .fraction(numerator: [], denominator: [])]])
    #expect(afterOperator.cursor.path.last?.slot == 0)

    var decimal = MathEditor()
    decimal.type("2+3.25")
    decimal.insertFraction()
    #expect(decimal.text == "2+((3.25)/())")

    var scaled = MathEditor()
    scaled.type("2x")
    scaled.insertFraction()
    scaled.type("3")
    #expect(try evaluate(scaled) == "2x/3")  // only the variable moved up: 2·(x/3)
  }

  @Test("A fraction written as a divisor keeps its meaning")
  func fractionAsDivisor() throws {
    var editor = MathEditor()
    editor.type("x÷")
    editor.insertFraction()
    editor.type("1")
    editor.moveRight()
    editor.type("2")
    #expect(try evaluate(editor) == "2x")  // x ÷ (1/2), not (x ÷ 1)/2
  }

  @Test("Exponents attach to the item before them")
  func powers() throws {
    var editor = MathEditor()
    editor.type("2")
    editor.insertPower()
    editor.type("3")
    #expect(editor.text == "2^(3)")
    #expect(try evaluate(editor) == "8")

    var group = MathEditor()
    group.type("(x+1)")
    group.insertPower()
    group.type("2")
    #expect(group.text == "(x+1)^(2)")

    var negative = MathEditor()
    negative.type("2")
    negative.insertPower()
    negative.type("−1")
    #expect(try evaluate(negative) == "1/2")

    var fractionPower = MathEditor()
    fractionPower.insertFraction()
    fractionPower.type("1")
    fractionPower.moveRight()
    fractionPower.type("2")
    fractionPower.moveRight()
    fractionPower.insertPower()
    fractionPower.type("2")
    #expect(try evaluate(fractionPower) == "1/4")  // (1/2)², not 1/(2²) read the wrong way round
  }

  @Test("Roots")
  func roots() throws {
    var square = MathEditor()
    square.insertRadical()
    square.type("12")
    #expect(square.text == "√(12)")
    #expect(try evaluate(square) == "2√3")

    var cube = MathEditor()
    cube.insertRadical(withIndex: true)
    cube.type("3")  // the cursor starts in the index
    cube.moveRight()
    cube.type("8")
    #expect(cube.text == "root(8,3)")
    #expect(try evaluate(cube) == "2")

    var nested = MathEditor()
    nested.insertRadical()
    nested.type("2+")
    nested.insertRadical()
    nested.type("9")
    #expect(try evaluate(nested) == "√5")
  }

  @Test("Parentheses open with the cursor inside and are closed by the closing key")
  func parentheses() throws {
    var editor = MathEditor()
    editor.type("(1+2)*3")
    #expect(editor.text == "(1+2)*3")
    #expect(try evaluate(editor) == "9")
    #expect(editor.cursor.path.isEmpty)

    var stray = MathEditor()
    stray.type("1)")  // nothing to close: ignored
    #expect(stray.text == "1")

    var nested = MathEditor()
    nested.type("((1+2)*(3+4))")
    #expect(try evaluate(nested) == "21")
    #expect(nested.cursor.path.isEmpty)
  }

  @Test("Functions hold their argument in parentheses")
  func functions() throws {
    var editor = MathEditor()
    editor.insertFunction("sin")
    editor.type("π")
    editor.type(")")
    editor.type("+1")
    #expect(editor.text == "sin(π)+1")
    #expect(try evaluate(editor) == "1")

    var logarithm = MathEditor()
    logarithm.insertFunction("log")
    logarithm.type("1000")
    #expect(try evaluate(logarithm) == "3")

    var bars = MathEditor()
    bars.insertAbsolute()
    bars.type("−5")
    #expect(try evaluate(bars) == "5")
  }

  @Test("Letters typed one by one are variables, never a function name")
  func letters() throws {
    var word = MathEditor()
    word.type("sin")
    #expect(word.text == "s*i*n")
    #expect(try evaluate(word) == "ins")  // the product of three variables, in alphabetical order

    var product = MathEditor()
    product.type("2x")
    #expect(product.text == "2x")
    product.type("y")
    #expect(product.text == "2x*y")

    var beforeFunction = MathEditor()
    beforeFunction.type("a")
    beforeFunction.insertFunction("sin")
    beforeFunction.type("x")
    #expect(beforeFunction.text == "a*sin(x)")  // not asin(x)

    var constants = MathEditor()
    constants.type("exp")
    #expect(constants.text == "e*x*p")
  }

  @Test("The cursor moves through structures in reading order and back")
  func movement() {
    var editor = MathEditor()
    editor.type("1")
    editor.insertFraction()  // 1 over ▢, cursor in the denominator
    editor.type("2")
    editor.moveRight()  // out of the fraction
    editor.type("+3")
    #expect(editor.cursor == MathCursor(line: 0, path: [], offset: 3))
    for _ in 0..<2 { editor.moveLeft() }
    #expect(editor.cursor == MathCursor(line: 0, path: [], offset: 1))  // just after the fraction
    editor.moveLeft()  // into the denominator, at its end
    #expect(editor.cursor == MathCursor(line: 0, path: [.init(index: 0, slot: 1)], offset: 1))
    editor.moveLeft()
    editor.moveLeft()  // denominator start, then the numerator end
    #expect(editor.cursor == MathCursor(line: 0, path: [.init(index: 0, slot: 0)], offset: 1))
    editor.moveLeft()
    editor.moveLeft()  // numerator start, then out to before the fraction
    #expect(editor.cursor == MathCursor(line: 0, path: [], offset: 0))
    editor.moveLeft()  // the start of the line: nowhere to go
    #expect(editor.cursor == MathCursor(line: 0, path: [], offset: 0))
  }

  @Test("Backspace removes symbols, enters filled structures, and removes empty ones")
  func backspace() {
    var editor = MathEditor()
    editor.type("12")
    editor.backspace()
    #expect(editor.text == "1")

    var fraction = MathEditor()
    fraction.type("1")
    fraction.insertFraction()
    fraction.type("2")
    fraction.backspace()  // the 2
    #expect(fraction.text == "((1)/())")
    fraction.backspace()  // at the start of the denominator: step back into the numerator
    #expect(fraction.cursor.path == [.init(index: 0, slot: 0)] && fraction.cursor.offset == 1)
    fraction.backspace()  // the 1
    #expect(fraction.text == "(()/())")
    fraction.backspace()  // everything is empty: the fraction goes
    #expect(fraction.isEmpty && fraction.cursor == MathCursor())

    var power = MathEditor()
    power.type("2")
    power.insertPower()
    power.type("3")
    power.backspace()
    power.backspace()
    #expect(power.text == "2" && power.cursor == MathCursor(line: 0, path: [], offset: 1))

    var whole = MathEditor()
    whole.type("1+")
    whole.insertFraction()
    whole.type("2")  // the numerator
    whole.moveRight()  // the (empty) denominator
    whole.moveRight()  // out of the fraction
    whole.backspace()  // after a filled fraction: enters it, from the end of its last slot
    #expect(whole.cursor.path == [.init(index: 2, slot: 1)] && whole.cursor.offset == 0)

    var empty = MathEditor()
    empty.backspace()  // nothing to delete
    #expect(empty.isEmpty)
  }

  @Test("Lines make a system, one equation each")
  func lines() throws {
    var editor = MathEditor()
    editor.type("x+y=3")
    editor.newLine()
    editor.type("x−y=1")
    #expect(editor.lines.count == 2)
    #expect(editor.text == "x+y=3\nx−y=1")
    #expect(throws: CalculatorError.unsupported(.system)) { try Calculator().evaluate(editor.text) }

    editor.newLine()
    #expect(editor.text == "x+y=3\nx−y=1")  // an empty line adds nothing
    editor.backspace()  // removes the empty line
    #expect(editor.lines.count == 2 && editor.cursor.line == 1)

    // The arrows go from line to line.
    var moving = MathEditor(lines: [[.symbol("a")], [.symbol("b")]])
    #expect(moving.cursor == MathCursor(line: 1, path: [], offset: 1))
    moving.moveLeft()
    moving.moveLeft()
    #expect(moving.cursor == MathCursor(line: 0, path: [], offset: 1))
    moving.moveRight()
    #expect(moving.cursor == MathCursor(line: 1, path: [], offset: 0))
  }

  @Test("Everything the keyboard can build is something the calculator understands")
  func endToEnd() throws {
    var editor = MathEditor()
    // sin(2π/3) with the fraction stacked: the fraction takes π as its numerator and the 2 stays in front of it.
    editor.insertFunction("sin")
    editor.type("2π")
    editor.insertFraction()  // the operand is π
    editor.type("3")
    #expect(editor.text == "sin(2((π)/(3)))")
    #expect(try evaluate(editor) == "√3/2")
  }

  @Test("Nodes survive being stored and read back")
  func codable() throws {
    let nodes: [MathNode] = [
      .symbol("2"), .fraction(numerator: [.symbol("1")], denominator: [.superscript([.symbol("x")])]),
      .radical(index: [.symbol("3")], radicand: [.group([.symbol("8")])]), .radical(index: nil, radicand: []),
      .function(name: "sin", argument: [.absolute([.symbol("π")])]),
    ]
    let data = try JSONEncoder().encode(nodes)
    #expect(try JSONDecoder().decode([MathNode].self, from: data) == nodes)
  }
}

private let traceEditorCases = ProcessInfo.processInfo.environment["MANTISSA_TRACE"] != nil

@Suite("Math editor properties")
struct MathEditorPropertyTests {
  /// Presses random keys. Whatever the sequence, the cursor stays on a real place, the text can always be written, the
  /// parser either reads it or rejects it cleanly, and walking right through every position and then left gives the
  /// same positions the other way round.
  @Test("Random key presses never leave the editor in an impossible state", arguments: [1, 2, 3, 4, 5, 6])
  func randomKeys(seed: Int) {
    var generator = SplitMix64(seed: UInt64(seed) &* 1_000_003)
    var editor = MathEditor()
    let symbols = ["0", "1", "2", "9", "+", "−", "×", "÷", "=", "x", "y", "π", "e", ".", "%", "!", "°", ","]
    for step in 0..<1500 {
      let key = Int(generator.next() % 17)
      switch key {
      case 0, 1, 2, 3, 4: editor.insert(symbols[Int(generator.next() % UInt64(symbols.count))])
      case 5: editor.insertFraction()
      case 6: editor.insertPower()
      case 7: editor.insertRadical(withIndex: generator.next() % 2 == 0)
      case 8: editor.insert("(")
      case 9: editor.insert(")")
      case 10: editor.insertFunction(["sin", "ln", "log", "cos"][Int(generator.next() % 4)])
      case 11: editor.insertAbsolute()
      case 12: editor.moveLeft()
      case 13: editor.moveRight()
      case 14, 15: editor.backspace()
      default:
        if generator.next() % 6 == 0 { editor.newLine() }
        if generator.next() % 60 == 0 { editor.clear() }
      }
      if traceEditorCases { FileHandle.standardError.write(Data("STEP \(seed) \(step) key \(key)\n".utf8)) }
      #expect(editor.isValid, "invalid cursor after step \(step), key \(key): \(editor.cursor)")
      guard editor.isValid else { return }

      if step % 25 == 0 {
        // The text can be written and read, or rejected without a crash.
        _ = try? Parser.parse(editor.text)
        let right = editor.positionsGoingRight()
        let left = editor.positionsGoingLeft()
        #expect(right == left.reversed(), "walking right and left disagree at step \(step)")
        #expect(Set(right).count == right.count, "a position was visited twice at step \(step)")
      }
    }
  }
}
