/// Solves systems of equations in several unknowns.
///
/// A system of linear equations is reduced by Gauss–Jordan elimination with exact arithmetic: it has one solution, none,
/// or infinitely many (some unknowns then stand for any number). Otherwise an unknown is eliminated through an equation
/// that is linear in it with a constant coefficient, and the rest is solved for the others, until one unknown is left.
enum SystemSolver {
  /// The unknowns in the order they are listed: `x`, `y`, `z`, then the other letters alphabetically.
  static func ordered(_ symbols: Set<String>) -> [String] {
    var result = ["x", "y", "z"].filter { symbols.contains($0) }
    result += symbols.subtracting(result).sorted()
    return result
  }

  /// Solves the equations `expression = 0` for the unknowns. `nil` when the system is not of a kind handled here.
  static func solve(_ equations: [Expr], unknowns: [String]) -> Solved? {
    if let linear = solveLinear(equations, unknowns: unknowns) { return linear }
    guard let solutions = substitute(equations, unknowns: unknowns) else { return nil }

    var tuples: [[SolvedValue]] = []
    for solution in solutions {
      var row: [SolvedValue] = []
      for name in unknowns {
        guard let value = solution[name], let solved = SolvedValue.exact(value) else { break }
        row.append(solved)
      }
      guard row.count == unknowns.count, satisfies(solution, equations) else { continue }
      tuples.append(row)
    }
    tuples = sortedAndDistinct(tuples)
    return tuples.isEmpty ? .none(variable: unknowns.first ?? "x") : .tuples(variables: unknowns, tuples)
  }

  // MARK: Linear systems

  /// `Σ coefficients[i]·unknown[i] + constant = 0`.
  private struct LinearEquation {
    var coefficients: [Expr]
    var constant: Expr
  }

  private static func linearForm(_ expression: Expr, unknowns: [String]) -> LinearEquation? {
    let source = expression.expanded()
    let terms: [Expr]
    if case .sum(let inner) = source { terms = inner } else { terms = [source] }
    var coefficients = Array(repeating: [Expr](), count: unknowns.count)
    var constants: [Expr] = []
    for term in terms {
      let present = unknowns.indices.filter { term.freeSymbols.contains(unknowns[$0]) }
      switch present.count {
      case 0:
        constants.append(term)
      case 1:
        let index = present[0]
        let unknown = Expr.symbol(unknowns[index])
        if term == unknown {
          coefficients[index].append(.one)
        } else if case .product(let factors) = term, let position = factors.firstIndex(of: unknown) {
          var rest = factors
          rest.remove(at: position)
          guard rest.allSatisfy({ $0.freeSymbols.isDisjoint(with: unknowns) }) else { return nil }
          coefficients[index].append(Expr.makeProduct(rest))
        } else {
          return nil
        }
      default:
        return nil
      }
    }
    return LinearEquation(coefficients: coefficients.map { Expr.makeSum($0) }, constant: Expr.makeSum(constants))
  }

  private static func solveLinear(_ equations: [Expr], unknowns: [String]) -> Solved? {
    var rows: [[Expr]] = []  // the unknowns' coefficients, then the right-hand side
    for equation in equations {
      guard let form = linearForm(equation, unknowns: unknowns) else { return nil }
      rows.append(form.coefficients + [-form.constant])
    }
    let columns = unknowns.count
    func isZero(_ value: Expr) -> Bool { value.isZeroValue }

    var pivots: [Int] = []  // pivots[r] is the column of row r's pivot
    var row = 0
    for column in 0..<columns where row < rows.count {
      guard let found = (row..<rows.count).first(where: { !isZero(rows[$0][column]) }) else { continue }
      rows.swapAt(row, found)
      let pivot = rows[row][column]
      for index in 0...columns {
        guard let scaled = try? rows[row][index].divided(by: pivot) else { return nil }
        rows[row][index] = scaled.expanded()
      }
      for other in rows.indices where other != row && !isZero(rows[other][column]) {
        let factor = rows[other][column]
        for index in 0...columns { rows[other][index] = (rows[other][index] - factor * rows[row][index]).expanded() }
      }
      pivots.append(column)
      row += 1
    }

    // A row with no unknowns left says `0 = something`.
    for index in row..<rows.count where !isZero(rows[index][columns]) { return .none(variable: unknowns.first ?? "x") }

    let free = unknowns.indices.filter { !pivots.contains($0) }
    if free.isEmpty {
      let values = pivots.indices.map { rows[$0][columns] }
      var tuple: [SolvedValue] = []
      for column in 0..<columns {
        guard let rowIndex = pivots.firstIndex(of: column), let value = SolvedValue.exact(values[rowIndex]) else {
          return nil
        }
        tuple.append(value)
      }
      return .tuples(variables: unknowns, [tuple])
    }

    var assignments: [Assignment] = []
    for (rowIndex, column) in pivots.enumerated() {
      var value = rows[rowIndex][columns]
      for f in free { value = value - rows[rowIndex][f] * Expr.symbol(unknowns[f]) }
      guard let solved = SolvedValue.exact(value.expanded()) else { return nil }
      assignments.append(Assignment(variable: unknowns[column], value: solved))
    }
    return .dependent(assignments, free: free.map { unknowns[$0] })
  }

  // MARK: Substitution

  /// The complete solutions of the system, each a value for every unknown, or `nil` when the system is beyond this method.
  private static func substitute(_ input: [Expr], unknowns: [String]) -> [[String: Expr]]? {
    var equations: [Expr] = []
    for equation in input.map({ $0.expanded() }) {
      if equation.freeSymbols.isDisjoint(with: unknowns) {
        if equation.isZeroValue { continue }
        return equation.freeSymbols.isEmpty ? [] : nil  // 0 = 3 has no solution; a = 3 is not decided here
      }
      equations.append(equation)
    }
    if equations.isEmpty { return unknowns.isEmpty ? [[:]] : nil }
    if unknowns.isEmpty { return nil }

    // Eliminate an unknown through an equation that is linear in it with a constant coefficient.
    for equation in equations.sorted(by: { $0.nodeCount < $1.nodeCount }) {
      for unknown in unknowns {
        guard let polynomial = equation.polynomial(in: unknown), polynomial.degree == 1,
          polynomial.coefficients[1].freeSymbols.isDisjoint(with: unknowns),
          let value = try? (-polynomial.coefficients[0]).divided(by: polynomial.coefficients[1])
        else { continue }
        var others: [Expr] = []
        for other in equations where other != equation {
          guard let replaced = other.substituting(unknown, with: value) else { return nil }
          others.append(replaced)
        }
        guard let inner = substitute(others, unknowns: unknowns.filter { $0 != unknown }) else { return nil }
        var results: [[String: Expr]] = []
        for solution in inner {
          var resolved: Expr? = value
          for (name, assigned) in solution { resolved = resolved?.substituting(name, with: assigned) }
          guard let final = resolved else { continue }
          var full = solution
          full[unknown] = final
          results.append(full)
        }
        return results
      }
    }

    // One unknown left in every equation: solve one and keep what satisfies the others.
    guard unknowns.count == 1, let unknown = unknowns.first,
      let solved = EquationSolver.solve(equations[0], for: unknown)
    else { return nil }
    switch solved {
    case .none: return []
    case .values(_, let values):
      var results: [[String: Expr]] = []
      for value in values {
        guard let exact = value.exact else { return nil }
        let holds = equations.dropFirst().allSatisfy { $0.substituting(unknown, with: exact)?.isZeroValue ?? false }
        if holds { results.append([unknown: exact]) }
      }
      return results
    default:
      return nil
    }
  }

  /// Whether the values satisfy every equation.
  private static func satisfies(_ solution: [String: Expr], _ equations: [Expr]) -> Bool {
    for equation in equations {
      var value: Expr? = equation
      for (name, assigned) in solution { value = value?.substituting(name, with: assigned) }
      guard let final = value, final.expanded().isZeroValue else { return false }
    }
    return true
  }

  // MARK: Ordering

  /// The solutions in increasing order of their first unknown, then the second, and so on, real ones first, with equal ones
  /// once.
  private static func sortedAndDistinct(_ tuples: [[SolvedValue]]) -> [[SolvedValue]] {
    func less(_ a: [SolvedValue], _ b: [SolvedValue]) -> Bool {
      for (x, y) in zip(a, b) {
        guard let p = x.approximation, let q = y.approximation else { continue }
        if p.isReal != q.isReal { return p.isReal }
        if p.real != q.real { return p.real < q.real }
        if p.imaginary != q.imaginary { return p.imaginary < q.imaginary }
      }
      return false
    }
    func close(_ a: [SolvedValue], _ b: [SolvedValue]) -> Bool {
      zip(a, b).allSatisfy { x, y in
        guard let p = x.approximation, let q = y.approximation else { return x.exact == y.exact }
        let scale = max(BigDecimal(1), p.real.magnitude, p.imaginary.magnitude)
        let tolerance = scale * BigDecimal(BigInt(1), exponent: -30)
        return (p.real - q.real).magnitude <= tolerance && (p.imaginary - q.imaginary).magnitude <= tolerance
      }
    }
    var result: [[SolvedValue]] = []
    for tuple in tuples.sorted(by: less) where !result.contains(where: { close($0, tuple) }) { result.append(tuple) }
    return result
  }
}
