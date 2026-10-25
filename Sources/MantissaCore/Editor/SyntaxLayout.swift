// Lays parsed text out as editor nodes, so that a formula typed elsewhere can be pasted into the editor and edited like one
// typed on the keyboard: fractions stacked, powers raised, roots with their bar.

extension MathEditor {
  /// The lines of the formula that `text` writes (one per equation of a system), or `nil` when it is not a complete formula.
  /// The text is what the parser reads: `2x^2 + sqrt(3)`, `x^2 + y^2 = 25`, `sin(π/6)`, one equation per line.
  public static func lines(fromText text: String) -> [[MathNode]]? {
    guard let statement = try? Parser.parse(text) else { return nil }
    return SyntaxLayout.lines(for: statement)
  }

  /// Puts nodes at the cursor and leaves the cursor after them.
  public mutating func insert(nodes: [MathNode]) {
    guard !nodes.isEmpty else { return }
    edit { sequence, offset in
      sequence.insert(contentsOf: nodes, at: offset)
      offset += nodes.count
    }
  }

  /// Pastes the formula `text` writes at the cursor. A system pastes its first equation there and the others on new lines
  /// after it. Returns false, and changes nothing, when the text is not a complete formula.
  @discardableResult
  public mutating func paste(_ text: String) -> Bool {
    guard let pasted = Self.lines(fromText: text), let first = pasted.first else { return false }
    insert(nodes: first)
    for line in pasted.dropFirst() {
      newLine()
      insert(nodes: line)
    }
    return true
  }
}

/// A formula as nodes, and how tightly it binds, so that one used where it would bind too loosely gets parentheses.
enum SyntaxLayout {
  private enum Level {
    static let sum = 1
    static let product = 2
    /// A number with a minus sign.
    static let sign = 3
    /// A power, or a number with `!`, `%` or `°`.
    static let power = 4
    static let atom = 5
  }

  private struct Piece {
    var nodes: [MathNode]
    var level: Int

    func wrapped(minimum: Int) -> [MathNode] { level < minimum ? [.group(nodes)] : nodes }
  }

  static func lines(for statement: Statement) -> [[MathNode]] {
    switch statement {
    case .expression(let syntax): return [piece(syntax).nodes]
    case .relation(let chain):
      var nodes = piece(chain.first).nodes
      for link in chain.links { nodes += [.symbol(symbol(of: link.op))] + piece(link.operand).nodes }
      return [nodes]
    case .system(let parts): return parts.flatMap { lines(for: $0) }
    }
  }

  private static func symbol(of op: RelationOperator) -> String {
    switch op {
    case .equal: return "="
    case .notEqual: return "≠"
    case .less: return "<"
    case .lessOrEqual: return "≤"
    case .greater: return ">"
    case .greaterOrEqual: return "≥"
    }
  }

  // MARK: Pieces

  private static func piece(_ syntax: Syntax) -> Piece {
    switch syntax {
    case .number(let value): return number(value)
    case .symbol(let name): return Piece(nodes: [.symbol(name)], level: Level.atom)
    case .constant(let constant): return Piece(nodes: [.symbol(constant.symbol)], level: Level.atom)
    case .infinity: return Piece(nodes: [.symbol("∞")], level: Level.atom)
    case .negate(let operand):
      return Piece(nodes: [.symbol("−")] + piece(operand).wrapped(minimum: Level.product), level: Level.sign)
    case .binary(let op, let left, let right): return binary(op, left, right)
    case .postfix(let op, let operand):
      let mark: String
      switch op {
      case .factorial: mark = "!"
      case .percent: mark = "%"
      case .degree: mark = "°"
      }
      return Piece(nodes: piece(operand).wrapped(minimum: Level.atom) + [.symbol(mark)], level: Level.power)
    case .call(let function, let arguments): return call(function, arguments)
    case .radical(let index, let radicand):
      return Piece(
        nodes: [.radical(index: index.map { piece($0).nodes }, radicand: piece(radicand).nodes)], level: Level.atom)
    case .matrix(let rows):
      return Piece(
        nodes: [.matrix(rows: rows.count, columns: rows[0].count, cells: rows.flatMap { $0 }.map { piece($0).nodes })],
        level: Level.atom)
    }
  }

  private static func number(_ value: Rational) -> Piece {
    let sign: [MathNode] = value.isNegative ? [.symbol("−")] : []
    let magnitude = value.magnitude
    let level = value.isNegative ? Level.sign : Level.atom
    if magnitude.isInteger {
      return Piece(nodes: sign + magnitude.numerator.description.map { .symbol(String($0)) }, level: level)
    }
    if let decimal = terminatingDecimal(magnitude) {
      return Piece(nodes: sign + decimal.map { .symbol(String($0)) }, level: level)
    }
    // One that does not end (1/3) is a fraction.
    let fraction = MathNode.fraction(
      numerator: magnitude.numerator.description.map { .symbol(String($0)) },
      denominator: magnitude.denominator.description.map { .symbol(String($0)) })
    return Piece(nodes: sign + [fraction], level: level)
  }

  /// `0.25` for 1/4, or `nil` when the digits go on for ever.
  private static func terminatingDecimal(_ value: Rational) -> String? {
    var rest = value.denominator
    var twos = 0
    var fives = 0
    while (rest % BigInt(2)).isZero {
      rest = rest / BigInt(2)
      twos += 1
    }
    while (rest % BigInt(5)).isZero {
      rest = rest / BigInt(5)
      fives += 1
    }
    guard rest.isOne else { return nil }
    let places = max(twos, fives)
    let scaled = value.numerator * (BigInt(10).power(places) / value.denominator)
    var digits = scaled.description
    if digits.count <= places { digits = String(repeating: "0", count: places - digits.count + 1) + digits }
    digits.insert(".", at: digits.index(digits.endIndex, offsetBy: -places))
    return digits
  }

  private static func binary(_ op: BinaryOperator, _ left: Syntax, _ right: Syntax) -> Piece {
    switch op {
    case .add:
      // a + (−b) is a − b.
      if case .negate(let operand) = right {
        let minuend = piece(left).wrapped(minimum: Level.sum)
        return Piece(
          nodes: minuend + [.symbol("−")] + piece(operand).wrapped(minimum: Level.product), level: Level.sum)
      }
      return Piece(
        nodes: piece(left).wrapped(minimum: Level.sum) + [.symbol("+")] + piece(right).wrapped(minimum: Level.sum),
        level: Level.sum)
    case .subtract:
      return Piece(
        nodes: piece(left).wrapped(minimum: Level.sum) + [.symbol("−")] + piece(right).wrapped(minimum: Level.product),
        level: Level.sum)
    case .multiply:
      let first = piece(left).wrapped(minimum: Level.product)
      let second = piece(right).wrapped(minimum: Level.sign)
      let joined = isImplicit(first, second) ? first + second : first + [.symbol("×")] + second
      return Piece(nodes: joined, level: Level.product)
    case .divide:
      return Piece(nodes: [.fraction(numerator: piece(left).nodes, denominator: piece(right).nodes)], level: Level.atom)
    case .power:
      return Piece(
        nodes: piece(left).wrapped(minimum: Level.atom) + [.superscript(piece(right).nodes)], level: Level.power)
    }
  }

  /// Whether the product reads as written side by side (2x, 3(x + 1), x sin x): what follows starts with a letter or a
  /// structure and what precedes ends with something that can be multiplied, and not with an operator.
  private static func isImplicit(_ left: [MathNode], _ right: [MathNode]) -> Bool {
    guard let start = right.first, let end = left.last else { return false }
    switch start {
    case .symbol(let text):
      guard let character = text.first, character.isLetter else { return false }
    case .superscript: return false
    default: break
    }
    switch end {
    case .symbol(let text):
      guard let character = text.first else { return false }
      return character.isLetter || character.isNumber || ["!", "%", "°", "∞"].contains(text)
    case .superscript: return true
    default: return true  // a structure: a fraction, a group, a root, a function
    }
  }

  // MARK: Calls

  private static func call(_ function: FunctionName, _ arguments: [Syntax]) -> Piece {
    func atom(_ node: MathNode) -> Piece { Piece(nodes: [node], level: Level.atom) }
    func list(_ arguments: [Syntax]) -> [MathNode] {
      var nodes: [MathNode] = []
      for (index, argument) in arguments.enumerated() {
        if index > 0 { nodes.append(.symbol(",")) }
        nodes += piece(argument).nodes
      }
      return nodes
    }

    switch function {
    case .sqrt: return atom(.radical(index: nil, radicand: list(arguments)))
    case .cbrt: return atom(.radical(index: [.symbol("3")], radicand: list(arguments)))
    case .root: return atom(.radical(index: piece(arguments[1]).nodes, radicand: piece(arguments[0]).nodes))
    case .abs: return atom(.absolute(list(arguments)))
    case .log where arguments.count == 2:
      return atom(.logarithm(base: piece(arguments[1]).nodes, argument: piece(arguments[0]).nodes))
    case .int, .sum, .lim, .diff:
      if let node = calculus(function, arguments) { return atom(node) }
    default: break
    }
    return atom(.function(name: function.rawValue, argument: list(arguments)))
  }

  /// ∫, Σ, lim or d/dx with its parts in their boxes, when the call has the form the boxes hold.
  private static func calculus(_ function: FunctionName, _ arguments: [Syntax]) -> MathNode? {
    func variable(at index: Int) -> [MathNode]? {
      guard arguments.count > index else { return nil }
      guard case .symbol(let name) = arguments[index] else { return nil }
      return [.symbol(name)]
    }
    let expression = piece(arguments[0]).nodes
    switch function {
    case .int:
      switch arguments.count {
      case 1: return .calculus(.integral, [expression, [.symbol("x")], [], []])
      case 2:
        guard let name = variable(at: 1) else { return nil }
        return .calculus(.integral, [expression, name, [], []])
      case 4:
        guard let name = variable(at: 1) else { return nil }
        return .calculus(.integral, [expression, name, piece(arguments[2]).nodes, piece(arguments[3]).nodes])
      default: return nil
      }
    case .sum:
      guard let name = variable(at: 1) else { return nil }
      return .calculus(.sum, [expression, name, piece(arguments[2]).nodes, piece(arguments[3]).nodes])
    case .lim:
      guard let name = variable(at: 1) else { return nil }
      var point = piece(arguments[2]).nodes
      if arguments.count == 4 {
        switch arguments[3] {
        case .number(let side) where side == Rational(1): point.append(.symbol("⁺"))
        case .negate(.number(let side)) where side == Rational(1): point.append(.symbol("⁻"))
        default: return nil
        }
      }
      return .calculus(.limit, [expression, name, point])
    default:  // diff
      guard arguments.count <= 2 else { return nil }
      return .calculus(.derivative, [expression, variable(at: 1) ?? [.symbol("x")]])
    }
  }
}
