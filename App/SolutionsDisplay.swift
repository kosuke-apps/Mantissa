import MantissaCore

/// What solving an equation, a system or an inequality came to, typeset for the screen and the history.
struct SolutionsDisplay: Equatable {
  enum Kind: Equatable {
    /// One line for each solution.
    case values
    /// No value works.
    case none
    /// Every value works (the lines say which are left out, as `x ≠ 1`).
    case everything
    /// A statement with no unknown, and whether it is true.
    case truth(Bool)
    /// A system with infinitely many solutions: one line for each unknown that depends on the `free` ones.
    case dependent(free: [String])
    /// An inequality: one line for each stretch (`x < −1`, `2 < x ≤ 5`), and the same in interval notation.
    case intervals
  }

  struct Line: Equatable {
    var exact: [MathNode]
    /// The decimal values, when they say something more than the exact ones do.
    var decimal: [MathNode]?
    /// Whether `decimal` names its unknowns (`x ≈ 1.41, y ≈ 2.23`) and so needs no `≈` sign in front.
    var decimalIsLabelled = false
  }

  var kind: Kind
  var lines: [Line] = []
  /// For an inequality, the solution set as `(−∞, −1) ∪ (2, ∞)`.
  var notation: [MathNode]?

  /// The answer on one line, for the history.
  var summary: [MathNode] {
    switch kind {
    case .values, .dependent:
      return Array(lines.map(\.exact).joined(separator: [MathNode.symbol(","), .symbol(" ")]))
    case .intervals: return notation ?? []
    case .none: return Self.text(String(localized: "No solution"))
    case .everything: return Self.text(String(localized: "Every number"))
    case .truth(let value): return Self.text(value ? String(localized: "True") : String(localized: "False"))
    }
  }

  private static func text(_ string: String) -> [MathNode] { string.map { .symbol(String($0)) } }

  init(kind: Kind, lines: [Line] = [], notation: [MathNode]? = nil) {
    self.kind = kind
    self.lines = lines
    self.notation = notation
  }

  /// Typesets a solution to `digits` significant digits in the decimals.
  init(_ solved: Solved, digits: Int) {
    switch solved {
    case .truth(let value):
      self.init(kind: .truth(value))
    case .none:
      self.init(kind: .none)
    case .everything(let variable, let excluding):
      let lines = excluding.map { value in
        Line(exact: [.symbol(variable), .symbol("≠")] + Self.nodes(of: value, digits: digits))
      }
      self.init(kind: .everything, lines: lines)
    case .values(let variable, let values):
      self.init(
        kind: .values, lines: values.map { Self.line([Assignment(variable: variable, value: $0)], digits: digits) })
    case .tuples(let variables, let rows):
      let lines = rows.map { row in
        Self.line(zip(variables, row).map { Assignment(variable: $0, value: $1) }, digits: digits)
      }
      self.init(kind: .values, lines: lines)
    case .dependent(let assignments, let free):
      self.init(kind: .dependent(free: free), lines: assignments.map { Self.line([$0], digits: digits) })
    case .intervals(let variable, let intervals):
      let lines = intervals.map { Line(exact: Self.inequality($0, variable: variable, digits: digits)) }
      self.init(kind: .intervals, lines: lines, notation: Self.notation(intervals, digits: digits))
    }
  }

  // MARK: Equations

  /// `x = 2` or `x = 3, y = 4`, with the decimals beneath when some value is not a whole number or has no exact form.
  private static func line(_ assignments: [Assignment], digits: Int) -> Line {
    var exact: [MathNode] = []
    var decimal: [MathNode] = []
    var needsDecimal = false
    for (index, assignment) in assignments.enumerated() {
      if index > 0 { exact += [.symbol(","), .symbol(" ")] }
      let name = MathNode.symbol(assignment.variable)
      let value = assignment.value
      guard let expression = value.exact else {
        exact += [name, .symbol("≈")] + decimalNodes(value.approximation, digits: digits)
        continue
      }
      exact += [name, .symbol("=")] + Typesetter.nodes(for: expression)
      guard value.approximation != nil, expression.rational?.isInteger != true, !expression.isGaussianInteger else {
        continue
      }
      if needsDecimal { decimal += [.symbol(","), .symbol(" ")] }
      needsDecimal = true
      decimal += [name, .symbol("≈")] + decimalNodes(value.approximation, digits: digits)
    }
    guard needsDecimal else { return Line(exact: exact) }
    if assignments.count == 1 {
      // One unknown: the decimal alone, beneath the exact value.
      return Line(exact: exact, decimal: Array(decimal.dropFirst(2)))
    }
    return Line(exact: exact, decimal: decimal, decimalIsLabelled: true)
  }

  private static func nodes(of value: SolvedValue, digits: Int) -> [MathNode] {
    value.exact.map { Typesetter.nodes(for: $0) } ?? decimalNodes(value.approximation, digits: digits)
  }

  private static func decimalNodes(_ value: ComplexDecimal?, digits: Int) -> [MathNode] {
    guard let value else { return [] }
    if value.isReal { return Typesetter.nodes(for: value.real, significantDigits: digits) }
    return Typesetter.nodes(for: value, significantDigits: digits)
  }

  // MARK: Inequalities

  /// `x < 3`, `x ≥ −1`, `1 < x ≤ 5` or, for a single point, `x = 2`.
  private static func inequality(_ interval: SolvedInterval, variable: String, digits: Int) -> [MathNode] {
    let name = MathNode.symbol(variable)
    if interval.isPoint, let lower = interval.lower {
      return [name, .symbol("=")] + bound(lower, digits: digits)
    }
    var result: [MathNode] = []
    if let lower = interval.lower {
      result += bound(lower, digits: digits) + [.symbol(lower.isClosed ? "≤" : "<")]
    }
    result.append(name)
    if let upper = interval.upper {
      result += [.symbol(upper.isClosed ? "≤" : "<")] + bound(upper, digits: digits)
    }
    if interval.lower == nil, let upper = interval.upper {
      return [name, .symbol(upper.isClosed ? "≤" : "<")] + bound(upper, digits: digits)
    }
    if interval.upper == nil, let lower = interval.lower {
      return [name, .symbol(lower.isClosed ? "≥" : ">")] + bound(lower, digits: digits)
    }
    return result
  }

  private static func bound(_ bound: SolvedBound, digits: Int) -> [MathNode] {
    if let exact = bound.value.exact { return Typesetter.nodes(for: exact) }
    return [.symbol("≈")] + decimalNodes(bound.value.approximation, digits: digits)
  }

  /// `(−∞, −1) ∪ [2, ∞)`, with `{3}` for a point.
  private static func notation(_ intervals: [SolvedInterval], digits: Int) -> [MathNode] {
    var result: [MathNode] = []
    for (index, interval) in intervals.enumerated() {
      if index > 0 { result.append(.symbol("∪")) }
      if interval.isPoint, let lower = interval.lower {
        result += [.symbol("{")] + bound(lower, digits: digits) + [.symbol("}")]
        continue
      }
      result.append(.symbol(interval.lower?.isClosed == true ? "[" : "("))
      if let lower = interval.lower {
        result += bound(lower, digits: digits)
      } else {
        result += [.symbol("−"), .symbol("∞")]
      }
      result += [.symbol(","), .symbol(" ")]
      if let upper = interval.upper { result += bound(upper, digits: digits) } else { result.append(.symbol("∞")) }
      result.append(.symbol(interval.upper?.isClosed == true ? "]" : ")"))
    }
    return result
  }
}
