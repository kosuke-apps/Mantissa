/// A curve or a region given by a relation between `x` and `y` that is not the graph of a function: a circle or an ellipse
/// (`x² + y² = 25`), a region (`y > x²`, `x² + y² ≤ 4`), or the part of the line where an inequality in `x` holds.
public struct PlotRelation: Sendable {
  public enum Kind: Sendable, Equatable {
    case equal, less, lessOrEqual, greater, greaterOrEqual
  }

  /// `left − right`: the relation says how this compares with zero.
  public let expression: Expr
  public let kind: Kind
  public let evaluate: PlaneFunction

  public init(expression: Expr, kind: Kind) {
    self.expression = expression
    self.kind = kind
    evaluate = DoubleCompiler.compilePlane(expression)
  }

  /// An inequality, which is drawn as a shaded region; an equation is only its boundary.
  public var isRegion: Bool { kind != .equal }

  /// Whether the points of the boundary belong to the region: a solid line for `≤` and `≥`, a dashed one for `<` and `>`.
  public var includesBoundary: Bool { kind != .less && kind != .greater }

  /// Whether a point where the expression has `value` satisfies the relation.
  public func holds(_ value: Double) -> Bool {
    switch kind {
    case .equal: return value == 0
    case .less: return value < 0
    case .lessOrEqual: return value <= 0
    case .greater: return value > 0
    case .greaterOrEqual: return value >= 0
    }
  }
}

/// Everything an input asks to be drawn: graphs of functions of `x`, and the other curves and regions.
public struct PlotContent: Sendable {
  public var functions: [PlotFunction]
  public var relations: [PlotRelation]

  public init(functions: [PlotFunction] = [], relations: [PlotRelation] = []) {
    self.functions = functions
    self.relations = relations
  }

  public var isEmpty: Bool { functions.isEmpty && relations.isEmpty }

  /// Whether `other` draws the same thing: the same expressions in the same order, with the same kinds of relation. A graph
  /// the user has moved is kept while the input changes into something that draws the same.
  public func draws(sameAs other: PlotContent) -> Bool {
    functions.map(\.expression) == other.functions.map(\.expression)
      && relations.map(\.expression) == other.relations.map(\.expression)
      && relations.map(\.kind) == other.relations.map(\.kind)
  }
}

extension Calculator {
  /// What the input describes that can be drawn: its functions of `x` (see `plotFunctions`) and its other relations in `x`
  /// and `y`. A system is drawn when every line of it is one or the other: a line and a circle, or the inequalities whose
  /// common part is the answer.
  public func plotContent(_ text: String) -> PlotContent {
    let functions = plotFunctions(text)
    if !functions.isEmpty { return PlotContent(functions: functions) }
    guard let statement = try? Parser.parse(text) else { return PlotContent() }
    let builder = Builder(angleUnit: settings.angleUnit)

    func relation(_ statement: Statement) -> PlotRelation? {
      guard case .relation(let chain) = statement, chain.links.count == 1 else { return nil }
      let kind: PlotRelation.Kind
      switch chain.links[0].op {
      case .equal: kind = .equal
      case .less: kind = .less
      case .lessOrEqual: kind = .lessOrEqual
      case .greater: kind = .greater
      case .greaterOrEqual: kind = .greaterOrEqual
      case .notEqual: return nil
      }
      guard let left = try? builder.build(chain.first), let right = try? builder.build(chain.links[0].operand) else {
        return nil
      }
      let difference = left - right
      let symbols = difference.freeSymbols
      guard !symbols.isEmpty, symbols.isSubset(of: ["x", "y"]), !difference.containsImaginaryUnit else { return nil }
      return PlotRelation(expression: difference, kind: kind)
    }

    switch statement {
    case .system(let lines):
      var content = PlotContent()
      for line in lines {
        // A line that is the graph of a function is drawn as one, and the others as relations.
        if let function = plotLine(line, builder) {
          content.functions.append(function)
        } else if let other = relation(line) {
          content.relations.append(other)
        } else {
          return PlotContent()
        }
      }
      return content
    default:
      guard let single = relation(statement) else { return PlotContent() }
      return PlotContent(relations: [single])
    }
  }
}
