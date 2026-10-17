// Writing a formula as the text the parser reads.
//
// The text is not meant to be pretty: it is exact. A fraction is wrapped in parentheses so that `x ÷ ½` and `½²` mean
// what they look like, an exponent is always `^(…)`, and two letters in a row are written with a multiplication sign so
// that the letters s, i, n typed one by one are three variables and not the function `sin`. Empty slots give empty
// parentheses, which the parser rejects: an unfinished formula is reported as such rather than guessed at.

extension MathNode {
  /// The node as text for `Parser`.
  public var parserText: String {
    switch self {
    case .symbol(let text): return text
    case .fraction(let numerator, let denominator):
      return "((" + numerator.parserText + ")/(" + denominator.parserText + "))"
    case .radical(let index, let radicand):
      guard let index else { return "√(" + radicand.parserText + ")" }
      return "root(" + radicand.parserText + "," + index.parserText + ")"
    case .superscript(let content): return "^(" + content.parserText + ")"
    case .group(let content): return "(" + content.parserText + ")"
    case .function(let name, let argument): return name + "(" + argument.parserText + ")"
    case .absolute(let content): return "abs(" + content.parserText + ")"
    case .logarithm(let base, let argument): return "log(" + argument.parserText + "," + base.parserText + ")"
    case .calculus(let kind, let slots):
      var arguments = [slots[0].parserText, slots[1].parserText]
      switch kind {
      case .integral:
        // An integral with no ends is indefinite; with either end it is definite, and a missing one is left empty so that the
        // formula reads as unfinished.
        if !slots[2].isEmpty || !slots[3].isEmpty { arguments += [slots[2].parserText, slots[3].parserText] }
      case .sum: arguments += [slots[2].parserText, slots[3].parserText]
      case .limit:
        // A small + or − after the point means from above or from below: `lim(f, x, 0, 1)`.
        var point = slots[2]
        var direction: String?
        if case .symbol(let mark)? = point.last, mark == "⁺" || mark == "⁻" {
          point.removeLast()
          direction = mark == "⁺" ? "1" : "-1"
        }
        arguments.append(point.parserText)
        if let direction { arguments.append(direction) }
      case .derivative: break
      }
      return kind.functionName + "(" + arguments.joined(separator: ",") + ")"
    }
  }

  fileprivate var isLetterSymbol: Bool { symbolCharacter?.isLetter ?? false }

  fileprivate var isFunction: Bool {
    switch self {
    case .function, .logarithm, .calculus: return true
    default: return false
    }
  }
}

extension Array where Element == MathNode {
  /// The sequence as text for `Parser`.
  public var parserText: String {
    var text = ""
    var previous: MathNode?
    for node in self {
      // A letter followed by a letter or a function name would be read as one longer name ("a" "sin" is "asin").
      if let previous, previous.isLetterSymbol, node.isLetterSymbol || node.isFunction { text += "*" }
      text += node.parserText
      previous = node
    }
    return text
  }
}

extension MathEditor {
  /// What has been typed, as the text `Parser` reads: one line per equation, empty lines left out.
  public var text: String {
    lines.map(\.parserText).filter { !$0.isEmpty }.joined(separator: "\n")
  }
}
