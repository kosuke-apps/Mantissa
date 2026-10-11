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
    }
  }

  fileprivate var isLetterSymbol: Bool { symbolCharacter?.isLetter ?? false }

  fileprivate var isFunction: Bool {
    if case .function = self { return true }
    return false
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
