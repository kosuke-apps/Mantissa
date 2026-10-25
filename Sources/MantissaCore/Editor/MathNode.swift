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
  /// A logarithm with its base written small below: `log₂(8)`. The base is the first slot and the argument the second.
  case logarithm(base: [MathNode], argument: [MathNode])
  /// ∫, Σ, lim and d/dx, each with the slots listed under `CalculusKind`.
  case calculus(CalculusKind, [[MathNode]])
  /// A matrix, or a vector when it has one column: `rows` × `columns` cells, row by row, each a sequence of its own. A cursor
  /// visits them in that order, so that → goes along a row and on to the next.
  case matrix(rows: Int, columns: Int, cells: [[MathNode]])
}

/// The operators of calculus the keyboard can place, and the slots each has, in the order the cursor visits them:
///
/// - `integral`: the integrand, the variable (`x`), the lower and the upper end (both empty for an indefinite integral);
/// - `sum`: the summand, the index (`k`), where it starts and where it ends;
/// - `limit`: the expression, the variable, the point it approaches;
/// - `derivative`: the expression and the variable.
public enum CalculusKind: String, Hashable, Sendable, Codable, CaseIterable {
  case integral, sum, limit, derivative

  /// The slots a new operator starts with: the variable is filled in, and a sum starts at 1 and runs to ∞.
  var initialSlots: [[MathNode]] {
    switch self {
    case .integral: return [[], [.symbol("x")], [], []]
    case .sum: return [[], [.symbol("k")], [.symbol("1")], [.symbol("∞")]]
    case .limit: return [[], [.symbol("x")], []]
    case .derivative: return [[], [.symbol("x")]]
    }
  }

  var slotCount: Int { initialSlots.count }

  /// The name of the function the parser knows it by.
  var functionName: String {
    switch self {
    case .integral: return "int"
    case .sum: return "sum"
    case .limit: return "lim"
    case .derivative: return "diff"
    }
  }
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
    case .logarithm: return 2
    case .calculus(let kind, _): return kind.slotCount
    case .matrix(_, _, let cells): return cells.count
    }
  }

  public func slot(_ index: Int) -> [MathNode] {
    switch self {
    case .symbol: preconditionFailure("A symbol has no slots")
    case .fraction(let numerator, let denominator): return index == 0 ? numerator : denominator
    case .radical(let rootIndex, let radicand): return rootIndex != nil && index == 0 ? rootIndex! : radicand
    case .superscript(let content), .group(let content), .absolute(let content): return content
    case .function(_, let argument): return argument
    case .logarithm(let base, let argument): return index == 0 ? base : argument
    case .calculus(_, let slots): return slots[index]
    case .matrix(_, _, let cells): return cells[index]
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
    case .logarithm(let base, let argument):
      return index == 0 ? .logarithm(base: content, argument: argument) : .logarithm(base: base, argument: content)
    case .calculus(let kind, var slots):
      slots[index] = content
      return .calculus(kind, slots)
    case .matrix(let rows, let columns, var cells):
      cells[index] = content
      return .matrix(rows: rows, columns: columns, cells: cells)
    }
  }

  /// True for a structure all of whose slots are empty (an unfilled fraction, bare parentheses, …). A calculus operator is
  /// empty when its expression is, whatever the variable and the ends say, so that backspace removes it.
  var isEmptyStructure: Bool {
    if case .calculus = self { return slot(0).isEmpty }
    return slotCount > 0 && (0..<slotCount).allSatisfy { slot($0).isEmpty }
  }

  /// Whether the node is a structure with slots (as opposed to a single symbol).
  var isStructure: Bool { slotCount > 0 }

  /// For a symbol: the glyph's first character.
  var symbolCharacter: Character? {
    if case .symbol(let text) = self { return text.first }
    return nil
  }
}
