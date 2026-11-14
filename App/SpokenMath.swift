import Foundation
import MantissaCore

/// A formula as it is to be spoken by VoiceOver: `x² − 5x + 6 = 0` as "x squared minus 5 x plus 6 equals 0", a fraction as "3 over 2",
/// a root as "square root of 6", a matrix row by row. The words are in the String Catalog, with numbered placeholders so that a
/// language can put the parts in its own order (Japanese says the denominator first).
///
/// `plainText` is for copying a formula out as text; this is for the ear.
enum SpokenMath {
  static func text(of nodes: [MathNode]) -> String {
    let spoken = speak(nodes)
    return spoken.isEmpty ? word("empty") : spoken
  }

  // MARK: Words

  private static func word(_ key: String) -> String { Localizer.string(key) }

  private static func phrase(_ key: String, _ parts: String...) -> String {
    String(format: Localizer.string(key), arguments: parts)
  }

  /// What a single character is called, when it is not a letter or a digit.
  private static let symbolWords: [String: String] = [
    "−": "minus", "+": "plus", "×": "times", "·": "times", "÷": "divided by", "=": "equals", "<": "is less than",
    ">": "is greater than", "≤": "is less than or equal to", "≥": "is greater than or equal to", "≠": "is not equal to",
    "π": "pi", "∞": "infinity", "°": "degrees", "!": "factorial", "%": "percent", ",": "comma", ";": "semicolon",
    "^": "to the power",
    "/": "over", "|": "bar", "[": "open bracket", "]": "close bracket", "{": "open brace", "}": "close brace",
    "(": "open parenthesis", ")": "close parenthesis", "⁻": "minus", "²": "squared", "³": "cubed", "¹": "1",
  ]

  private static let functionWords: [String: String] = [
    "sin": "sine", "cos": "cosine", "tan": "tangent", "asin": "arcsine", "acos": "arccosine", "atan": "arctangent",
    "sinh": "hyperbolic sine", "cosh": "hyperbolic cosine", "tanh": "hyperbolic tangent", "ln": "natural log",
    "log": "log",
    "exp": "exponential", "sqrt": "square root", "cbrt": "cube root", "abs": "absolute value", "floor": "floor",
    "ceil": "ceiling",
    "round": "round", "det": "determinant", "inverse": "inverse", "transpose": "transpose", "trace": "trace",
    "rank": "rank",
  ]

  // MARK: Speaking

  private static func speak(_ nodes: [MathNode]) -> String {
    var parts: [String] = []
    // The characters of a number or a name are one word: "1", "2", ".", "5" is "12.5".
    var joinable = false
    for node in nodes {
      switch node {
      case .symbol(let symbol):
        if let word = symbolWords[symbol] {
          parts.append(Localizer.string(word))
          joinable = false
        } else if joinable, let last = parts.last, isNumeric(symbol), isNumeric(String(last.suffix(1))) {
          parts[parts.count - 1] = last + symbol
        } else {
          parts.append(symbol)
          joinable = isNumeric(symbol)
        }
        // A decimal point between digits is part of the number.
        if symbol == ".", parts.count >= 2, isNumeric(String(parts[parts.count - 2].suffix(1))) {
          parts.removeLast()
          parts[parts.count - 1] += "."
          joinable = true
        }
      case .superscript(let exponent):
        let base = parts.popLast() ?? ""
        let spokenExponent = speak(exponent)
        switch spokenExponent {
        case "2": parts.append(phrase("%@ squared", base))
        case "3": parts.append(phrase("%@ cubed", base))
        default: parts.append(phrase("%1$@ to the power %2$@", base, spokenExponent))
        }
        joinable = false
      default:
        parts.append(structure(node))
        joinable = false
      }
    }
    return parts.joined(separator: " ")
  }

  private static func isNumeric(_ text: String) -> Bool {
    text.allSatisfy { $0.isNumber || $0 == "." } && !text.isEmpty
  }

  private static func slot(_ nodes: [MathNode]) -> String {
    let spoken = speak(nodes)
    return spoken.isEmpty ? word("empty") : spoken
  }

  /// Whether a slot is a single character, so that it needs no "end of" to tell where it stops.
  private static func isSimple(_ nodes: [MathNode]) -> Bool {
    if nodes.count == 1, case .symbol = nodes[0] { return true }
    return nodes.allSatisfy { if case .symbol(let text) = $0 { return isNumeric(text) } else { return false } }
  }

  private static func structure(_ node: MathNode) -> String {
    switch node {
    case .symbol, .superscript:
      return ""
    case .fraction(let numerator, let denominator):
      let over = phrase("%1$@ over %2$@", slot(numerator), slot(denominator))
      return isSimple(numerator) && isSimple(denominator) ? over : phrase("the fraction %@, end of fraction", over)
    case .radical(let index, let radicand):
      if let index {
        return phrase("root %1$@ of %2$@", slot(index), slot(radicand))
      }
      return isSimple(radicand)
        ? phrase("square root of %@", slot(radicand)) : phrase("the square root of %@, end of root", slot(radicand))
    case .group(let inner):
      return phrase("open parenthesis %@ close parenthesis", slot(inner))
    case .function(let name, let argument):
      let spokenName = functionWords[name].map { Localizer.string($0) } ?? name
      return phrase("%1$@ of %2$@", spokenName, slot(argument))
    case .absolute(let inner):
      return phrase("absolute value of %@", slot(inner))
    case .logarithm(let base, let argument):
      return phrase("log base %1$@ of %2$@", slot(base), slot(argument))
    case .calculus(let kind, let slots):
      return calculus(kind, slots)
    case .matrix(let rows, let columns, let cells):
      return matrix(rows: rows, columns: columns, cells: cells)
    }
  }

  private static func calculus(_ kind: CalculusKind, _ slots: [[MathNode]]) -> String {
    func at(_ index: Int) -> [MathNode] { index < slots.count ? slots[index] : [] }
    switch kind {
    case .integral:
      // The integrand, the variable, the lower and the upper end.
      if at(2).isEmpty && at(3).isEmpty {
        return phrase("integral of %1$@ with respect to %2$@", slot(at(0)), slot(at(1)))
      }
      return phrase(
        "integral from %3$@ to %4$@ of %1$@ with respect to %2$@", slot(at(0)), slot(at(1)), slot(at(2)), slot(at(3)))
    case .sum:
      return phrase("sum of %1$@ for %2$@ from %3$@ to %4$@", slot(at(0)), slot(at(1)), slot(at(2)), slot(at(3)))
    case .limit:
      return phrase("limit of %1$@ as %2$@ approaches %3$@", slot(at(0)), slot(at(1)), slot(at(2)))
    case .derivative:
      return phrase("derivative of %1$@ with respect to %2$@", slot(at(0)), slot(at(1)))
    }
  }

  private static func matrix(rows: Int, columns: Int, cells: [[MathNode]]) -> String {
    func cell(_ row: Int, _ column: Int) -> String {
      let index = row * columns + column
      return index < cells.count ? slot(cells[index]) : word("empty")
    }
    let comma = word(", ")
    if columns == 1 {
      let entries = (0..<rows).map { cell($0, 0) }.joined(separator: comma)
      return phrase("vector with %1$@ entries: %2$@", String(rows), entries)
    }
    let spokenRows = (0..<rows).map { row in
      phrase("row %1$@: %2$@.", String(row + 1), (0..<columns).map { cell(row, $0) }.joined(separator: comma))
    }
    return phrase(
      "matrix with %1$@ rows and %2$@ columns. %3$@", String(rows), String(columns), spokenRows.joined(separator: " "))
  }
}
