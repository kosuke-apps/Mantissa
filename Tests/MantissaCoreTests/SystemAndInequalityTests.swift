import Testing

@testable import MantissaCore

/// Systems of equations and inequalities. Each expectation was worked out by hand.
@Suite("Systems and inequalities")
struct SystemAndInequalityTests {
  private func describe(_ value: SolvedValue) -> String {
    if let exact = value.exact { return exact.description }
    let z = value.approximation!
    return "≈" + (z.isReal ? "\(z.real.rounded(toSignificantDigits: 5))" : "\(z.rounded(toSignificantDigits: 5))")
  }

  /// Each solution of a system as `x=2, y=1`.
  private func tuples(_ text: String) throws -> [String] {
    switch try Calculator().solve(text) {
    case .tuples(let variables, let rows):
      return rows.map { row in zip(variables, row).map { "\($0)=\(describe($1))" }.joined(separator: ", ") }
    case .values(let variable, let values):
      return values.map { "\(variable)=\(describe($0))" }
    default:
      Issue.record("\(text) did not give solutions")
      return []
    }
  }

  @Test(
    "Linear systems with one solution",
    arguments: [
      ("x+y=3, x-y=1", ["x=2, y=1"]), ("2x+3y=7, x-y=1", ["x=2, y=1"]), ("2x+y=10, x+2y=8", ["x=4, y=2"]),
      ("x+y+z=6, x-y=0, z=3", ["x=3/2, y=3/2, z=3"]), ("x/2+y/3=1, x-y=2", ["x=2, y=0"]),
      ("a+b=3, a-b=1", ["a=2, b=1"]), ("x+y=1/2, x-y=1/3", ["x=5/12, y=1/12"]),
      ("x+y=2, x-y=0, x+2y=3", ["x=1, y=1"]), ("x+1=3, x-1=1", ["x=2"]), ("y=x, y=-x+4", ["x=2, y=2"]),
      ("3x-2y=4\nx+y=7", ["x=18/5, y=17/5"]),
    ])
  func linear(input: String, expected: [String]) throws {
    #expect(try tuples(input) == expected, "\(input)")
  }

  @Test("Systems with no solution, and with infinitely many")
  func degenerate() throws {
    #expect(try Calculator().solve("x+y=1, x+y=2") == .none(variable: "x"))
    #expect(try Calculator().solve("x+y=2, x-y=0, x=5") == .none(variable: "x"))
    #expect(try Calculator().solve("x=1, x=2") == .none(variable: "x"))

    guard case .dependent(let assignments, let free) = try Calculator().solve("x+y=5, 2x+2y=10") else {
      Issue.record("expected a family of solutions")
      return
    }
    #expect(free == ["y"])
    #expect(assignments.map { "\($0.variable)=\($0.value.exact!)" } == ["x=-y + 5"])

    guard case .dependent(let more, let freeMore) = try Calculator().solve("x+y+z=3, x-y=0") else {
      Issue.record("expected a family of solutions")
      return
    }
    #expect(freeMore == ["z"])
    #expect(more.map { "\($0.variable)=\($0.value.exact!)" } == ["x=-z/2 + 3/2", "y=-z/2 + 3/2"])
  }

  @Test(
    "Systems with a nonlinear equation",
    arguments: [
      ("x+y=7, x*y=12", ["x=3, y=4", "x=4, y=3"]), ("x²+y²=25, x+y=7", ["x=3, y=4", "x=4, y=3"]),
      ("y=x², y=2x+3", ["x=-1, y=1", "x=3, y=9"]), ("x²+y²=1, x=y", ["x=-√2/2, y=-√2/2", "x=√2/2, y=√2/2"]),
      ("x²=4, x=2", ["x=2"]), ("x²+y=3, x-y=3", ["x=-3, y=-6", "x=2, y=-1"]),
      ("x²+y²=2, x+y=0", ["x=-1, y=1", "x=1, y=-1"]),
    ])
  func nonlinear(input: String, expected: [String]) throws {
    #expect(try tuples(input) == expected, "\(input)")
  }

  @Test("Complex solutions of a system")
  func complexSystem() throws {
    #expect(try tuples("x²+y²=-2, x=y") == ["x=-i, y=-i", "x=i, y=i"])
    #expect(try tuples("x+y=2, x*y=2") == ["x=1 - i, y=1 + i", "x=1 + i, y=1 - i"])
  }

  // MARK: Inequalities

  private func describe(_ bound: SolvedBound?, lower: Bool) -> String {
    guard let bound else { return lower ? "(-∞" : "∞)" }
    let text = describe(bound.value)
    return lower ? (bound.isClosed ? "[" : "(") + text : text + (bound.isClosed ? "]" : ")")
  }

  /// The solution set as `(2, ∞)`, `(-∞, -2] ∪ [2, ∞)`, `{0}`, `∅` or `ℝ`.
  private func set(_ text: String) throws -> String {
    switch try Calculator().solve(text) {
    case .none: return "∅"
    case .everything: return "ℝ"
    case .truth(let value): return value ? "true" : "false"
    case .intervals(_, let intervals):
      return intervals.map { interval in
        interval.isPoint
          ? "{\(describe(interval.lower!.value))}"
          : describe(interval.lower, lower: true) + ", " + describe(interval.upper, lower: false)
      }.joined(separator: " ∪ ")
    default:
      Issue.record("\(text) did not give a set")
      return ""
    }
  }

  @Test(
    "Polynomial inequalities",
    arguments: [
      ("x>2", "(2, ∞)"), ("x≥2", "[2, ∞)"), ("x<2", "(-∞, 2)"), ("2x+1≤x-3", "(-∞, -4]"),
      ("x²<4", "(-2, 2)"), ("x²≤4", "[-2, 2]"), ("x²>4", "(-∞, -2) ∪ (2, ∞)"), ("x²≥4", "(-∞, -2] ∪ [2, ∞)"),
      ("x²-5x+6<0", "(2, 3)"), ("x²-5x+6≥0", "(-∞, 2] ∪ [3, ∞)"), ("(x-1)(x-2)(x-3)≥0", "[1, 2] ∪ [3, ∞)"),
      ("x²+1>0", "ℝ"), ("x²+1<0", "∅"), ("x²≤0", "{0}"), ("x²>0", "(-∞, 0) ∪ (0, ∞)"), ("x²<x", "(0, 1)"),
      ("x²-2>0", "(-∞, -√2) ∪ (√2, ∞)"), ("x≠2", "(-∞, 2) ∪ (2, ∞)"), ("(x-1)²≥0", "ℝ"),
      ("(x-1)²>0", "(-∞, 1) ∪ (1, ∞)"),
      ("x³-x>0", "(-1, 0) ∪ (1, ∞)"), ("-x²+4x-3>0", "(1, 3)"), ("x>x", "∅"), ("x≤x", "ℝ"),
    ])
  func polynomial(input: String, expected: String) throws {
    #expect(try set(input) == expected, "\(input)")
  }

  @Test(
    "Fractions, chains and statements with no unknown",
    arguments: [
      ("(x-1)/(x+2)>0", "(-∞, -2) ∪ (1, ∞)"), ("(x-1)/(x+2)≥0", "(-∞, -2) ∪ [1, ∞)"),
      ("(x-1)/(x+2)<0", "(-2, 1)"), ("1/x<1", "(-∞, 0) ∪ (1, ∞)"), ("1/x>0", "(0, ∞)"),
      ("(x²-1)/(x-1)≥0", "[-1, 1) ∪ (1, ∞)"), ("1<x≤5", "(1, 5]"), ("-1<x²<4", "(-2, 2)"), ("0<x<x²", "(1, ∞)"),
      ("1<2", "true"), ("3≤2", "false"), ("1<2<3", "true"), ("1<2<2", "false"), ("√2<1.5", "true"),
    ])
  func fractions(input: String, expected: String) throws {
    #expect(try set(input) == expected, "\(input)")
  }

  @Test("A bound that has no closed form is a decimal")
  func numericBound() throws {
    #expect(try set("x³-2x-5>0") == "(≈2.0946, ∞)")
  }

  @Test("Inequalities with several unknowns are not solved")
  func severalUnknowns() {
    #expect(throws: CalculatorError.unsupported(.equation)) { try Calculator().solve("x+y>2") }
  }

  /// Random linear systems built from a chosen solution: the solver returns exactly that solution; when the matrix is
  /// singular, whatever it returns is consistent with every equation.
  @Test("Random linear systems")
  func randomLinear() throws {
    var random = SplitMix64(seed: 5150)
    func int(_ range: ClosedRange<Int>) -> Int { Int(random.next() % UInt64(range.count)) + range.lowerBound }
    let names = ["x", "y", "z"]
    var solved = 0

    for _ in 0..<150 {
      let n = int(2...3)
      let solution = (0..<n).map { _ in Rational(int(-6...6), int(1...3)) }
      var equations: [String] = []
      var matrix: [[Int]] = []
      for _ in 0..<(n + int(0...1)) {
        let row = (0..<n).map { _ in int(-5...5) }
        matrix.append(row)
        var right = Rational(0)
        var left = ""
        for (index, coefficient) in row.enumerated() {
          right += Rational(coefficient) * solution[index]
          left += "\(coefficient < 0 ? "-" : "+")\(abs(coefficient))*\(names[index])"
        }
        equations.append("\(left)=\(right)")
      }
      let result = try Calculator().solve(equations.joined(separator: ", "))
      let rank = Self.rank(of: matrix)
      switch result {
      case .tuples(let variables, let rows):
        #expect(rank == n, "\(equations): unique solution but rank \(rank)")
        #expect(variables == Array(names.prefix(n)))
        #expect(rows.count == 1)
        #expect(rows[0].map { $0.exact } == solution.map { Expr.number($0) }, "\(equations)")
        solved += 1
      case .dependent(let assignments, let free):
        #expect(rank < n, "\(equations): family of solutions but rank \(rank)")
        #expect(assignments.count + free.count == n)
        // The chosen solution is a member of the family: the free unknowns take their chosen values, and the rest then follow.
        var values: [String: Expr] = [:]
        for (index, name) in names.prefix(n).enumerated() where free.contains(name) {
          values[name] = .number(solution[index])
        }
        for assignment in assignments {
          var value = try #require(assignment.value.exact)
          for (name, free) in values { value = try #require(value.substituting(name, with: free)) }
          let index = try #require(names.firstIndex(of: assignment.variable))
          #expect(value == .number(solution[index]), "\(equations): \(assignment.variable)")
        }
      default:
        Issue.record("\(equations): \(result)")
      }
    }
    #expect(solved > 40)
  }

  private static func rank(of matrix: [[Int]]) -> Int {
    var rows = matrix.map { $0.map { Rational($0) } }
    var rank = 0
    for column in 0..<(rows.first?.count ?? 0) {
      guard let pivot = (rank..<rows.count).first(where: { !rows[$0][column].isZero }) else { continue }
      rows.swapAt(rank, pivot)
      for other in rows.indices where other != rank {
        let factor = rows[other][column] / rows[rank][column]
        for index in rows[other].indices { rows[other][index] -= factor * rows[rank][index] }
      }
      rank += 1
    }
    return rank
  }

  /// Random polynomial inequalities, some built from chosen roots: at many test points the inequality holds exactly where
  /// the returned set contains the point.
  @Test("Random inequalities agree with direct evaluation")
  func randomInequalities() throws {
    var random = SplitMix64(seed: 8_675_309)
    func int(_ range: ClosedRange<Int>) -> Int { Int(random.next() % UInt64(range.count)) + range.lowerBound }
    let operators: [(String, RelationOperator)] = [
      ("<", .less), ("≤", .lessOrEqual), (">", .greater), ("≥", .greaterOrEqual),
    ]
    var checked = 0

    for round in 0..<150 {
      var coefficients: [Int]
      if round % 2 == 0 {
        coefficients = [int(1...2) * (int(0...1) == 0 ? 1 : -1)]
        for _ in 0..<int(1...4) {
          let root = int(-4...4)
          var next = Array(repeating: 0, count: coefficients.count + 1)
          for (power, coefficient) in coefficients.enumerated() {
            next[power + 1] += coefficient
            next[power] -= root * coefficient
          }
          coefficients = next
        }
      } else {
        coefficients = (0...int(1...4)).map { _ in int(-6...6) }
        if coefficients.last == 0 { coefficients[coefficients.count - 1] = int(1...6) }
      }
      let (symbol, op) = operators[int(0...3)]
      var text = ""
      for (power, coefficient) in coefficients.enumerated() where coefficient != 0 {
        text += "\(coefficient < 0 ? "-" : "+")\(abs(coefficient))*x^\(power)"
      }
      guard !text.isEmpty else { continue }
      let result = try Calculator().solve(text + symbol + "0")

      for step in -45...45 {
        let x = Rational(step, 5) + Rational(1, 97)  // away from the simple roots
        var value = Rational(0)
        for coefficient in coefficients.reversed() { value = value * x + Rational(coefficient) }
        let truth: Bool
        switch op {
        case .less: truth = value.signum < 0
        case .lessOrEqual: truth = value.signum <= 0
        case .greater: truth = value.signum > 0
        default: truth = value.signum >= 0
        }
        let inside: Bool
        switch result {
        case .none: inside = false
        case .everything: inside = true
        case .intervals(_, let intervals):
          inside = intervals.contains { interval in
            let aboveLower =
              interval.lower.map { bound in
                let lower = bound.value.approximation!.real
                let point = BigDecimal(x, precision: 50)
                return bound.isClosed ? point >= lower : point > lower
              } ?? true
            let belowUpper =
              interval.upper.map { bound in
                let upper = bound.value.approximation!.real
                let point = BigDecimal(x, precision: 50)
                return bound.isClosed ? point <= upper : point < upper
              } ?? true
            return aboveLower && belowUpper
          }
        default:
          Issue.record("\(text)\(symbol)0: \(result)")
          inside = truth
        }
        #expect(inside == truth, "\(text)\(symbol)0 at \(x): set says \(inside)")
      }
      checked += 1
    }
    #expect(checked > 100)
  }
}
