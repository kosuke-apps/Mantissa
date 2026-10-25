// A formula as text for people and other programs: `(√6 − √2)/4`, `x² …` as `x^2`, `x = 2, x = 3`.
//
// This is for copying an answer out of the app. `parserText` is for the parser and is not meant to be read: it wraps every
// fraction and exponent in parentheses.

extension Array where Element == MathNode {
  public var plainText: String {
    var text = ""
    for (index, node) in enumerated() {
      // `e^3e^x` would read as e^(3e^x), and `√x√2` as √(x√2): a product after a power or a root gets a dot.
      if index > 0, Self.endsWithTightOperand(self[index - 1]), Self.startsOperand(node) { text += "·" }
      switch node {
      case .symbol(let symbol):
        if Self.spaced.contains(symbol) {
          // A sign sits against what it applies to: at the start, or after another operator, a comma or a bracket.
          let isSign = (symbol == "−" || symbol == "+") && precedesOperand(index)
          if isSign {
            text += symbol
          } else {
            text += " " + symbol + " "
          }
        } else if symbol == "," {
          text += ", "
        } else {
          text += symbol
        }
      default:
        text += node.plainText
      }
    }
    // Two spaces can meet where an operator follows a comma.
    while text.contains("  ") { text = text.replacingOccurrences(of: "  ", with: " ") }
    return text.trimmingSpaces()
  }

  private static func endsWithTightOperand(_ node: MathNode) -> Bool {
    switch node {
    case .superscript: return true
    case .radical(let index, _): return index == nil
    default: return false
    }
  }

  /// Whether the node starts a factor: a letter, a digit, a constant or a structure, and not an operator or a mark.
  private static func startsOperand(_ node: MathNode) -> Bool {
    switch node {
    case .symbol(let text):
      guard let first = text.first else { return false }
      return first.isLetter || first.isNumber || first == "∞"
    case .superscript: return false
    default: return true
    }
  }

  private static var spaced: Set<String> { ["+", "−", "×", "÷", "=", "<", ">", "≤", "≥", "≠"] }

  /// Whether the node at `index` starts an operand: it is first, or follows an operator, a comma or an opening bracket.
  private func precedesOperand(_ index: Int) -> Bool {
    var before = index - 1
    // Spacing the answers put in (after a comma) does not matter here.
    while before >= 0, case .symbol(" ") = self[before] { before -= 1 }
    guard before >= 0 else { return true }
    guard case .symbol(let previous) = self[before] else { return false }
    return Self.spaced.contains(previous) || [",", "(", "["].contains(previous)
  }

  /// Whether the text is one term, which can stand next to `/`, `^` or `√` without brackets: `x`, `12`, `sin(x)`, `π`.
  fileprivate var isSingleTerm: Bool { plainText.isSingleTerm }
}

extension String {
  fileprivate func trimmingSpaces() -> String {
    var result = self
    while result.hasPrefix(" ") { result.removeFirst() }
    while result.hasSuffix(" ") { result.removeLast() }
    return result
  }

  /// A number, a single letter or constant, a function call, or something already in brackets or bars: what can follow `^`
  /// or `√`, or be a denominator, with no brackets of its own. `2x` is not one (`e^2x` would read as (e²)x).
  fileprivate var isAtomic: Bool {
    guard !isEmpty else { return true }
    if allSatisfy({ $0.isNumber || $0 == "." }) { return true }
    if count == 1 { return true }
    if hasPrefix("√") { return String(dropFirst()).isAtomic }
    guard let last, last == ")" || last == "|" else { return false }
    // The bracket that closes the last one must be the one the text starts with, or after a function name.
    var depth = 0
    var opening: Index?
    for index in indices {
      if self[index] == "(" {
        if depth == 0 { opening = index }
        depth += 1
      } else if self[index] == ")" {
        depth -= 1
        if depth == 0 && index != self.index(before: endIndex) { return false }
      }
    }
    if last == "|" { return first == "|" && dropFirst().dropLast().allSatisfy { $0 != "|" } }
    guard let opening else { return false }
    if opening == startIndex { return true }  // in brackets
    // A function call is one thing; `πcosh(x)` is π times one, and `xcosh(x)` is x times one.
    var name = String(self[..<opening])
    if name.hasPrefix("log") && name.count > 3 { name = "log" }  // log₂(8), log_x(8)
    return FunctionName.allCases.contains { $0.rawValue == name }
  }

  /// One term: it does not start with a minus sign and has no space, sum, product or quotient outside brackets.
  fileprivate var isSingleTerm: Bool {
    if isEmpty { return true }
    if hasPrefix("−") || hasPrefix("-") { return false }
    var depth = 0
    for character in self {
      switch character {
      case "(", "|": depth += character == "(" ? 1 : 0
      case ")": depth -= 1
      case " ", "+", "−", "-", "×", "÷", "/", "=", "<", ">", "≤", "≥", "≠", ",":
        if depth == 0 { return false }
      default: break
      }
    }
    return true
  }
}

extension MathNode {
  /// The node as text, as `[MathNode].plainText` joins it.
  public var plainText: String {
    /// `nodes` in brackets unless they are atomic (strict) or a single term.
    func bracketed(_ nodes: [MathNode], strict: Bool = true) -> String {
      let text = nodes.plainText
      return (strict ? text.isAtomic : text.isSingleTerm) ? text : "(" + text + ")"
    }
    switch self {
    case .symbol(let text): return text
    case .fraction(let numerator, let denominator):
      return bracketed(numerator, strict: false) + "/" + bracketed(denominator)
    case .radical(let index, let radicand):
      guard let index else { return "√" + bracketed(radicand) }
      return "root(" + radicand.plainText + ", " + index.plainText + ")"
    case .superscript(let content): return "^" + bracketed(content)
    case .group(let content): return "(" + content.plainText + ")"
    case .function(let name, let argument): return name + "(" + argument.plainText + ")"
    case .absolute(let content):
      // Bars inside bars cannot be told apart, so the inner ones are written out.
      let inner = content.plainText
      return inner.contains("|") ? "abs(" + inner + ")" : "|" + inner + "|"
    case .logarithm(let base, let argument):
      let subscripts: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
      ]
      let digits = base.plainText
      let written =
        !digits.isEmpty && digits.allSatisfy { $0.isNumber && subscripts[$0] != nil }
        ? String(digits.map { subscripts[$0]! }) : "_" + bracketed(base)
      return "log" + written + "(" + argument.plainText + ")"
    case .calculus(let kind, let slots):
      return kind.functionName + "(" + slots.map(\.plainText).joined(separator: ", ") + ")"
    case .matrix(let rows, let columns, let cells):
      let lines = (0..<rows).map { row in
        "[" + (0..<columns).map { cells[row * columns + $0].plainText }.joined(separator: ", ") + "]"
      }
      return "[" + lines.joined(separator: ", ") + "]"
    }
  }
}
