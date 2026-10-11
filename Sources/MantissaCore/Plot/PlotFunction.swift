/// A function of `x` that can be drawn: the exact expression and a fast `Double` version of it.
public struct PlotFunction: Sendable {
  public let expression: Expr
  public let evaluate: RealFunction

  public init(_ expression: Expr) {
    self.expression = expression
    evaluate = DoubleCompiler.compile(expression)
  }
}

extension Calculator {
  /// The functions of `x` that the input describes, when it describes nothing else: an expression in `x` (`x² − 4`), or
  /// a line `y = …` in `x` (`y = 2x + 1`, `y = 3`), or several such lines. Anything else (an expression with no unknown, an
  /// equation to solve, a line that mentions another letter, a formula that is not finished) gives an empty list.
  public func plotFunctions(_ text: String) -> [PlotFunction] {
    guard let statement = try? Parser.parse(text) else { return [] }
    let builder = Builder(angleUnit: settings.angleUnit)

    func function(_ syntax: Syntax, requiresUnknown: Bool) -> PlotFunction? {
      guard let expression = try? builder.build(syntax) else { return nil }
      let symbols = expression.freeSymbols
      guard symbols.isSubset(of: ["x"]), !requiresUnknown || !symbols.isEmpty else { return nil }
      return PlotFunction(expression)
    }

    func line(_ statement: Statement) -> PlotFunction? {
      switch statement {
      case .expression(let syntax):
        return function(syntax, requiresUnknown: true)
      case .relation(let chain):
        guard chain.links.count == 1, chain.links[0].op == .equal else { return nil }
        if chain.first == .symbol("y") { return function(chain.links[0].operand, requiresUnknown: false) }
        if chain.links[0].operand == .symbol("y") { return function(chain.first, requiresUnknown: false) }
        return nil
      case .system:
        return nil
      }
    }

    switch statement {
    case .system(let lines):
      let functions = lines.compactMap(line)
      return functions.count == lines.count ? functions : []
    default:
      return line(statement).map { [$0] } ?? []
    }
  }
}
