/// One piece of a typeset formula: a character, or a structure (fraction, root, exponent, parentheses, function call)
/// that holds one or more *slots*, each a sequence of nodes of its own.
///
/// The same tree is what the editor edits and what an answer is typeset into, so one view can draw both.
public indirect enum MathNode: Hashable, Sendable, Codable {
  /// One glyph: a digit, a letter, `+`, `×`, `=`, `π`, `!`, `°`, …
  case symbol(String)
  case fraction(numerator: [MathNode], denominator: [MathNode])
  /// A root. `index` is `nil` for a square root; otherwise it is the (possibly still empty) index.
  case radical(index: [MathNode]?, radicand: [MathNode])
  /// The exponent of whatever comes just before it in the sequence.
  case superscript([MathNode])
  /// Parentheses around a sequence.
  case group([MathNode])
  /// A named function with its argument in parentheses: `sin(…)`, `ln(…)`.
  case function(name: String, argument: [MathNode])
  /// Absolute-value bars.
  case absolute([MathNode])
}

extension MathNode {
  /// How many sequences the node contains: 0 for a symbol, 2 for a fraction, and so on. A cursor moves through them
  /// in this order (numerator before denominator, index before radicand).
  public var slotCount: Int {
    switch self {
    case .symbol: return 0
    case .fraction: return 2
    case .radical(let index, _): return index == nil ? 1 : 2
    case .superscript, .group, .function, .absolute: return 1
    }
  }

  public func slot(_ index: Int) -> [MathNode] {
    switch self {
    case .symbol: preconditionFailure("A symbol has no slots")
    case .fraction(let numerator, let denominator): return index == 0 ? numerator : denominator
    case .radical(let rootIndex, let radicand): return rootIndex != nil && index == 0 ? rootIndex! : radicand
    case .superscript(let content), .group(let content), .absolute(let content): return content
    case .function(_, let argument): return argument
    }
  }

  public func replacingSlot(_ index: Int, with content: [MathNode]) -> MathNode {
    switch self {
    case .symbol: preconditionFailure("A symbol has no slots")
    case .fraction(let numerator, let denominator):
      return index == 0
        ? .fraction(numerator: content, denominator: denominator)
        : .fraction(numerator: numerator, denominator: content)
    case .radical(let rootIndex, let radicand):
      if rootIndex != nil && index == 0 { return .radical(index: content, radicand: radicand) }
      return .radical(index: rootIndex, radicand: content)
    case .superscript: return .superscript(content)
    case .group: return .group(content)
    case .absolute: return .absolute(content)
    case .function(let name, _): return .function(name: name, argument: content)
    }
  }

  /// True for a structure all of whose slots are empty (an unfilled fraction, bare parentheses, …).
  var isEmptyStructure: Bool {
    slotCount > 0 && (0..<slotCount).allSatisfy { slot($0).isEmpty }
  }

  /// Whether the node is a structure with slots (as opposed to a single symbol).
  var isStructure: Bool { slotCount > 0 }

  /// For a symbol: the glyph's first character.
  var symbolCharacter: Character? {
    if case .symbol(let text) = self { return text.first }
    return nil
  }
}
