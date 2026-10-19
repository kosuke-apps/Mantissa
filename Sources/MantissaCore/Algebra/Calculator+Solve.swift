extension Calculator {
  /// Solves what the input says: an equation or inequality in one unknown (the unknown is `x` if there is one, otherwise
  /// `y`, `z` or the first letter alphabetically; other letters are constants for an equation), or a system of equations in
  /// several. An input that is not of that kind, or of a kind that cannot be solved yet, is `CalculatorError.unsupported`.
  ///
  /// With `variable`, a single equation with several letters is solved for that one (`F = m a` for `m`) instead of the default.
  public func solve(_ text: String, for variable: String? = nil) throws(CalculatorError) -> Solved {
    let statement: Statement
    do {
      statement = try Parser.parse(text)
    } catch {
      throw .parse(error)
    }
    let builder = Builder(angleUnit: settings.angleUnit)
    switch statement {
    case .expression:
      throw .unsupported(.equation)
    case .relation(let chain):
      if chain.links.count == 1, chain.links[0].op == .equal {
        return try solveEquation(chain, builder, preferred: variable)
      }
      return try solveInequality(chain, builder)
    case .system(let statements):
      return try solveSystem(statements, builder)
    }
  }

  private func build(_ syntax: Syntax, _ builder: Builder) throws(CalculatorError) -> Expr {
    do {
      return try builder.build(syntax)
    } catch {
      throw .math(error)
    }
  }

  // MARK: One equation

  private func solveEquation(
    _ chain: RelationChain, _ builder: Builder, preferred: String? = nil
  ) throws(CalculatorError) -> Solved {
    let left = try build(chain.first, builder)
    let right = try build(chain.links[0].operand, builder)
    // The unknown is looked for in what was typed, not in the difference, so that `x + 1 = x` (which has none left after
    // subtracting) is an equation with no solution and not a false statement.
    let letters = left.freeSymbols.union(right.freeSymbols)
    let chosen = preferred.flatMap { letters.contains($0) ? $0 : nil }
    // `y = f(x)` defines a function (it is drawn, not solved); `y = x²` is not an equation to solve for x. Unless the unknown was
    // asked for: then it is solved for that letter.
    let definesFunction =
      chosen == nil
      && ((chain.first == .symbol("y") && right.freeSymbols.isSubset(of: ["x"]))
        || (chain.links[0].operand == .symbol("y") && left.freeSymbols.isSubset(of: ["x"])))
    if definesFunction { throw .unsupported(.equation) }
    let difference = left - right
    guard let variable = chosen ?? EquationSolver.unknown(in: letters) else { return .truth(difference.isZeroValue) }
    guard let solved = EquationSolver.solve(difference, for: variable) else { throw .unsupported(.equation) }
    return solved
  }

  /// The letters a single equation could be solved for, the one it is solved for by default first; empty for anything else (an
  /// inequality, a system, an equation with one letter or none).
  public func unknowns(in text: String) -> [String] {
    guard case .relation(let chain)? = try? Parser.parse(text), chain.links.count == 1, chain.links[0].op == .equal
    else { return [] }
    let builder = Builder(angleUnit: settings.angleUnit)
    guard let left = try? builder.build(chain.first), let right = try? builder.build(chain.links[0].operand) else {
      return []
    }
    let letters = left.freeSymbols.union(right.freeSymbols)
    guard letters.count >= 2, let first = EquationSolver.unknown(in: letters) else { return [] }
    return [first] + letters.subtracting([first]).sorted()
  }

  // MARK: Inequalities

  private func solveInequality(_ chain: RelationChain, _ builder: Builder) throws(CalculatorError) -> Solved {
    var operands = [try build(chain.first, builder)]
    for link in chain.links { operands.append(try build(link.operand, builder)) }

    var constraints: [InequalitySolver.Constraint] = []
    for (index, link) in chain.links.enumerated() {
      constraints.append(.init(expression: operands[index] - operands[index + 1], op: link.op))
    }

    let letters = operands.reduce(into: Set<String>()) { $0.formUnion($1.freeSymbols) }
    if letters.isEmpty {
      // No unknown: the statement is true or false.
      for constraint in constraints {
        let sign: Int
        if constraint.expression.isZeroValue {
          sign = 0
        } else if let value = try? constraint.expression.approximation(precision: 40) {
          sign = value.isNegative ? -1 : 1
        } else {
          throw .unsupported(.equation)
        }
        if !InequalitySolver.satisfies(constraint.op, sign: sign) { return .truth(false) }
      }
      return .truth(true)
    }
    guard letters.count == 1, let variable = letters.first else { throw .unsupported(.equation) }
    if let solved = InequalitySolver.solve(constraints, variable: variable) { return solved }
    // sin x > 1/2: the same stretches in every period.
    if constraints.count == 1, let solved = PeriodicInequalities.solve(constraints[0], variable) { return solved }
    throw .unsupported(.equation)
  }

  // MARK: Systems

  private func solveSystem(_ statements: [Statement], _ builder: Builder) throws(CalculatorError) -> Solved {
    var equations: [Expr] = []
    for statement in statements {
      guard case .relation(let chain) = statement, chain.links.count == 1, chain.links[0].op == .equal else {
        throw .unsupported(.system)
      }
      equations.append(try build(chain.first, builder) - build(chain.links[0].operand, builder))
    }

    let letters = equations.reduce(into: Set<String>()) { $0.formUnion($1.freeSymbols) }
    if letters.isEmpty { return .truth(equations.allSatisfy(\.isZeroValue)) }
    let unknowns = SystemSolver.ordered(letters)
    guard let solved = SystemSolver.solve(equations, unknowns: unknowns) else { throw .unsupported(.system) }

    // One unknown left in the end is just an equation.
    if case .tuples(let variables, let tuples) = solved, variables.count == 1 {
      return .values(variable: variables[0], tuples.map { $0[0] })
    }
    return solved
  }
}
