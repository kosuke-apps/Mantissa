import Testing

@testable import MantissaCore

/// One- and two-variable statistics, against Python's `fractions` (`tools/gen_statistics_vectors.py`) and against values worked out
/// by hand.
@Suite("Statistics")
struct StatisticsTests {
  // MARK: Helpers

  private struct OneVariable: Decodable {
    var data: [String]
    var frequencies: [Int]?
    var count: Int
    var total: String
    var sumsq: String
    var mean: String
    var median: String
    var q1: String
    var q3: String
    var min: String
    var max: String
    var range: String
    var variance: String?
    var varp: String
    var modes: [String]?
    var percentiles: [Percentile]

    struct Percentile: Decodable {
      var p: String
      var value: String
    }
  }

  private struct TwoVariables: Decodable {
    var x: [String]
    var y: [String]
    var cov: String
    var covp: String
    var slope: String
    var intercept: String
    var determination: String
    var correlationSign: Int
  }

  private struct Polynomial: Decodable {
    var x: [String]
    var y: [String]
    var degree: Int
    var coefficients: [String]
    var determination: String?
  }

  private struct Transformed: Decodable {
    var kind: String
    var x: [String]
    var y: [String]
    var a: String
    var b: String
    var r: String
    var determination: String
  }

  private struct Vectors: Decodable {
    var one: [OneVariable]
    var two: [TwoVariables]
    var polynomials: [Polynomial]
    var transformed: [Transformed]
  }

  private static func load() throws -> Vectors { try loadVectors("statistics-vectors", as: Vectors.self) }

  /// The exact value of an input that comes to a number.
  private func value(_ text: String) throws -> Expr {
    do { return try Calculator().evaluate(text).exact } catch {
      Issue.record("\(text) failed with \(error)")
      throw error
    }
  }

  /// What an input comes to, when it is a column of numbers.
  private func column(_ text: String) throws -> [Expr] {
    switch try Calculator().compute(text) {
    case .matrix(let matrix): return matrix.entries
    case .number(let number): return [number.exact]
    default:
      Issue.record("\(text) is not a column")
      return []
    }
  }

  private func failure(_ text: String) -> CalculatorError? {
    do {
      _ = try Calculator().compute(text)
      return nil
    } catch { return error }
  }

  private func vector(_ items: [String], row: Bool = false) -> String {
    row ? "[[" + items.joined(separator: ",") + "]]" : "[" + items.map { "[\($0)]" }.joined(separator: ",") + "]"
  }

  private func report(_ text: String) throws -> [Report.Label: [Expr]] {
    guard case .report(let report) = try Calculator().compute(text) else {
      Issue.record("\(text) is not a report")
      return [:]
    }
    return Dictionary(uniqueKeysWithValues: report.rows.map { ($0.label, $0.values) })
  }

  // MARK: By hand

  @Test("the textbook data set: 2, 4, 4, 4, 5, 5, 7, 9")
  func textbook() throws {
    let data = "2, 4, 4, 4, 5, 5, 7, 9"
    #expect(try value("count(\(data))") == 8)
    #expect(try value("total(\(data))") == 40)
    #expect(try value("sumsq(\(data))") == 232)
    #expect(try value("mean(\(data))") == 5)
    #expect(try value("median(\(data))") == .fraction(9, 2))
    #expect(try value("varp(\(data))") == 4)
    #expect(try value("stdevp(\(data))") == 2)
    #expect(try value("variance(\(data))") == .fraction(32, 7))
    #expect(try value("stdev(\(data))") == (try Expr.fraction(32, 7).raised(to: .fraction(1, 2))))
    #expect(try value("min(\(data))") == 2)
    #expect(try value("max(\(data))") == 9)
    #expect(try value("range(\(data))") == 7)
    #expect(try column("mode(\(data))") == [4])
  }

  @Test("quartiles are the medians of the halves, and a middle datum belongs to neither half")
  func quartiles() throws {
    #expect(try value("quartile([[1],[2],[3],[4],[5],[6],[7],[8]], 1)") == .fraction(5, 2))
    #expect(try value("quartile([[1],[2],[3],[4],[5],[6],[7],[8]], 2)") == .fraction(9, 2))
    #expect(try value("quartile([[1],[2],[3],[4],[5],[6],[7],[8]], 3)") == .fraction(13, 2))
    // 1…9: the halves are 1…4 and 6…9, the 5 is in neither.
    #expect(try value("quartile([[1],[2],[3],[4],[5],[6],[7],[8],[9]], 1)") == .fraction(5, 2))
    #expect(try value("quartile([[1],[2],[3],[4],[5],[6],[7],[8],[9]], 3)") == .fraction(15, 2))
    #expect(try value("iqr(1,2,3,4,5,6,7,8,9)") == 5)
    // One value is all three quartiles.
    #expect(try value("quartile([[7]], 1)") == 7)
    #expect(try value("quartile([[7],[9]], 3)") == 9)
    // The textbook example 7, 15, 36, 39, 40, 41: Q1 = 15, Q3 = 40.
    #expect(try value("quartile([[7],[15],[36],[39],[40],[41]], 1)") == 15)
    #expect(try value("quartile([[7],[15],[36],[39],[40],[41]], 3)") == 40)
  }

  @Test("percentiles interpolate between neighbours")
  func percentiles() throws {
    #expect(try value("percentile([[1],[2],[3],[4]], 50)") == .fraction(5, 2))
    #expect(try value("percentile([[1],[2],[3],[4]], 25)") == .fraction(7, 4))
    #expect(try value("percentile([[1],[2],[3],[4]], 0)") == 1)
    #expect(try value("percentile([[1],[2],[3],[4]], 100)") == 4)
    #expect(try value("percentile([[10],[20]], 12.5)") == .fraction(45, 4))
  }

  @Test("values with frequencies")
  func frequencies() throws {
    // 1 three times, 3 once: 1, 1, 1, 3.
    #expect(try value("mean([[1],[2],[3]], [[3],[0],[1]])") == .fraction(3, 2))
    #expect(try value("count([[1],[2],[3]], [[3],[0],[1]])") == 4)
    #expect(try value("median([[1],[2],[3]], [[3],[0],[1]])") == 1)
    #expect(try column("mode([[1],[2],[3]], [[3],[0],[1]])") == [1])
    #expect(try value("total([[10],[20]], [[1000000],[3]])") == 10_000_060)
  }

  @Test("modes: all of the most frequent, none when every value is as frequent as the others")
  func modes() throws {
    #expect(try column("mode(3,1,3,1,2)") == [1, 3])
    #expect(try column("mode(5,5,5)") == [5])
    #expect(try column("mode(7)") == [7])
    #expect(failure("mode(1,2,3)") == .math(.noMode))
    #expect(failure("mode(1,1,2,2)") == .math(.noMode))
  }

  @Test("sort gives a column, ascending, with each value as often as it occurs")
  func sorting() throws {
    #expect(try column("sort(3,1,2,1)") == [1, 1, 2, 3])
    #expect(try column("sort([[2],[1]], [[2],[1]])") == [1, 2, 2])
    #expect(try value("mean(sort(4,2,6))") == 4)
  }

  @Test("numbers that are not whole: fractions, decimals, roots")
  func exactData() throws {
    #expect(try value("mean(1/3, 2/3, 1)") == .fraction(2, 3))
    #expect(try value("mean(0.1, 0.2, 0.3)") == .fraction(1, 5))
    #expect(try value("varp(1, 2, 3, 4)") == .fraction(5, 4))
    // √2 and 2√2: the mean is 3√2/2, found without a decimal.
    #expect(try value("mean(√2, 2√2)") == (Expr.fraction(3, 2) * (try Expr.integer(2).raised(to: .fraction(1, 2)))))
    // The order of √2 and 3/2 is judged by their values.
    #expect(try value("median(√2, 3/2, 1)") == (try Expr.integer(2).raised(to: .fraction(1, 2))))
    #expect(try value("max(√2, 3/2)") == .fraction(3, 2))
  }

  // MARK: Against the oracle

  @Test("one variable: every statistic of 54 data sets, in every way of writing them")
  func oneVariableOracle() throws {
    for item in try Self.load().one {
      var forms: [String]
      if let frequencies = item.frequencies {
        let counts = frequencies.map(String.init)
        // Two columns, a column and a row, and a row of each.
        // A row has at most 10 entries; a column up to 200.
        forms = [vector(item.data) + "," + vector(counts)]
        if item.data.count <= Matrix.maxColumns {
          forms.append(vector(item.data, row: true) + "," + vector(counts, row: true))
        }
      } else {
        forms = [item.data.joined(separator: ","), vector(item.data)]
        if item.data.count <= Matrix.maxColumns { forms.append(vector(item.data, row: true)) }
      }
      for arguments in forms {
        func same(_ function: String, _ expected: String) throws {
          let got = try value("\(function)(\(arguments))")
          let want = try value(expected)
          #expect(got == want, "\(function)(\(arguments)) = \(got), expected \(expected)")
        }
        try same("count", String(item.count))
        try same("total", item.total)
        try same("sumsq", item.sumsq)
        try same("mean", item.mean)
        try same("median", item.median)
        try same("min", item.min)
        try same("max", item.max)
        try same("range", item.range)
        try same("varp", item.varp)
        try same("iqr", "(\(item.q3))-(\(item.q1))")
        if let variance = item.variance { try same("variance", variance) }
        // The deviations are the roots of the variances.
        let populationDeviation = try value("stdevp(\(arguments))")
        #expect(populationDeviation == (try value(item.varp).raised(to: .fraction(1, 2))))
        if let variance = item.variance {
          #expect(try value("stdev(\(arguments))") == (try value(variance).raised(to: .fraction(1, 2))))
        } else {
          #expect(failure("stdev(\(arguments))") == .math(.insufficientData))
        }
        if let modes = item.modes {
          #expect(try column("mode(\(arguments))") == (try modes.map { try value($0) }))
        } else {
          #expect(failure("mode(\(arguments))") == .math(.noMode))
        }
        // The quartiles and percentiles take the data as one vector.
      }
      if item.frequencies == nil {
        let data = vector(item.data)
        #expect(try value("quartile(\(data), 1)") == (try value(item.q1)))
        #expect(try value("quartile(\(data), 2)") == (try value(item.median)))
        #expect(try value("quartile(\(data), 3)") == (try value(item.q3)))
        for percentile in item.percentiles {
          #expect(
            try value("percentile(\(data), \(percentile.p))") == (try value(percentile.value)),
            "percentile \(percentile.p) of \(item.data)")
        }
      }
    }
  }

  @Test("two variables: covariance, line and correlation of 24 data sets, as a table and as two vectors")
  func twoVariableOracle() throws {
    for item in try Self.load().two {
      let table = "[" + zip(item.x, item.y).map { "[\($0),\($1)]" }.joined(separator: ",") + "]"
      let separate = vector(item.x) + "," + vector(item.y)
      for arguments in [table, separate] {
        #expect(try value("cov(\(arguments))") == (try value(item.cov)))
        #expect(try value("covp(\(arguments))") == (try value(item.covp)))
        #expect(try value("slope(\(arguments))") == (try value(item.slope)))
        #expect(try value("intercept(\(arguments))") == (try value(item.intercept)))
        let r = try value("corr(\(arguments))")
        #expect((r * r).expanded() == (try value(item.determination)))
        #expect(r.numericSign == item.correlationSign)
      }
    }
  }

  // MARK: Regressions

  private func table(_ xs: [String], _ ys: [String]) -> String {
    "[" + zip(xs, ys).map { "[\($0),\($1)]" }.joined(separator: ",") + "]"
  }

  /// Whether two decimals agree to 45 significant digits (or absolutely, for a value that is zero).
  private func agree(_ a: BigDecimal, _ b: BigDecimal) -> Bool {
    let tolerance = BigDecimal(BigInt(1), exponent: -45)
    return (a - b).magnitude <= (b.isZero ? tolerance : b.magnitude * tolerance)
  }

  private func decimals(_ text: String, _ label: Report.Label) throws -> [BigDecimal] {
    guard case .report(let report) = try Calculator().compute(text) else { return [] }
    return report.rows.first { $0.label == label }?.approximations ?? []
  }

  @Test(
    "polynomial fits: exact coefficients and R² of 12 data sets, and the residual is orthogonal to every power of x")
  func polynomialOracle() throws {
    for item in try Self.load().polynomials {
      let rows = try report("polyreg(\(table(item.x, item.y)), \(item.degree))")
      for (power, expected) in item.coefficients.enumerated() {
        #expect(rows[.coefficient(power)] == [try value(expected)], "degree \(item.degree), coefficient of x^\(power)")
      }
      if let determination = item.determination {
        #expect(rows[.determination] == [try value(determination)], "R² of degree \(item.degree)")
      } else {
        #expect(rows[.determination] == nil)
      }
      #expect(rows[.count] == [.integer(item.x.count)])
    }
  }

  @Test("exponential, power and logarithmic fits agree to 45 digits with an independent decimal computation")
  func transformedOracle() throws {
    for item in try Self.load().transformed {
      let function = ["exponential": "expreg", "power": "powreg", "logarithmic": "logreg"][item.kind]!
      let text = "\(function)(\(table(item.x, item.y)))"
      let expected: [(Report.Label, String)] = [
        (.parameterA, item.a), (.parameterB, item.b), (.correlation, item.r), (.determination, item.determination),
      ]
      for (label, digits) in expected {
        let got = try decimals(text, label)
        let want = try #require(BigDecimal(digits))
        #expect(got.count == 1 && agree(got[0], want), "\(item.kind) \(label): \(got) against \(digits)")
      }
    }
  }

  @Test("curves that fit exactly are found: y = 2·3ˣ, y = 3x², y = 1 + 2 ln x, and a parabola")
  func exactCurves() throws {
    let a = BigDecimal(BigInt(1), exponent: -50)
    func near(_ got: [BigDecimal], _ want: Int) -> Bool { got.count == 1 && (got[0] - BigDecimal(want)).magnitude < a }
    let exponential = "expreg([[0,2],[1,6],[2,18],[3,54]])"
    #expect(near(try decimals(exponential, .parameterA), 2))
    #expect(near(try decimals(exponential, .parameterB), 3))
    #expect(near(try decimals(exponential, .determination), 1))
    let power = "powreg([[1,3],[2,12],[4,48],[5,75]])"
    #expect(near(try decimals(power, .parameterA), 3))
    #expect(near(try decimals(power, .parameterB), 2))
    let logarithm = "logreg([[1,1],[2,1+2ln(2)],[4,1+4ln(2)],[8,1+6ln(2)]])"
    #expect(near(try decimals(logarithm, .parameterA), 1))
    #expect(near(try decimals(logarithm, .parameterB), 2))
    // y = x² − 2x + 3 through four points: the coefficients are exact whole numbers, and R² is 1.
    let parabola = try report("polyreg([[0,3],[1,2],[2,3],[3,6]], 2)")
    #expect(parabola[.coefficient(2)] == [1])
    #expect(parabola[.coefficient(1)] == [-2])
    #expect(parabola[.coefficient(0)] == [3])
    #expect(parabola[.determination] == [1])
    #expect(parabola[.equation] == [try value("x^2-2x+3")])
  }

  @Test("a regression says what is wrong with the data")
  func regressionErrors() throws {
    #expect(failure("expreg([[1,2],[2,0],[3,5]])") == .math(.domain))
    #expect(failure("expreg([[1,2],[2,-1],[3,5]])") == .math(.domain))
    #expect(failure("powreg([[0,2],[1,3],[2,5]])") == .math(.domain))
    #expect(failure("logreg([[-1,2],[1,3],[2,5]])") == .math(.domain))
    #expect(failure("polyreg([[1,2],[2,3],[3,5]], 7)") == .math(.domain))
    #expect(failure("polyreg([[1,2],[2,3],[3,5]], 0)") == .math(.domain))
    #expect(failure("polyreg([[1,2],[2,3],[3,5]], 3)") == .math(.insufficientData))
    #expect(failure("polyreg([[1,2],[1,3],[1,5],[1,7]], 2)") == .math(.degenerateData))
    #expect(failure("polyreg([[1,2],[2,3],[3,5]])") != nil)
    #expect(failure("expreg([[2,2],[2,3],[2,5]])") == .math(.degenerateData))
    // All y equal: a fit that is perfect has no r.
    let flat = try Calculator().compute("expreg([[1,5],[2,5],[3,5]])")
    guard case .report(let report) = flat else {
      Issue.record("no report")
      return
    }
    #expect(report.rows.first { $0.label == .correlation } == nil)
    #expect(report.model == .exponential)
  }

  @Test("a regression is drawn: the points and the curve fitted to them")
  func regressionPlot() throws {
    let content = Calculator().plotContent("linreg([[1,2],[2,4],[3,5],[4,4],[5,5]])")
    #expect(content.points.count == 5)
    #expect(content.functions.count == 1)
    #expect(abs(content.functions[0].evaluate(3) - (0.6 * 3 + 2.2)) < 1e-12)
    let window = PlotViewport.fit(content)
    for point in content.points {
      #expect(window.xMin < point.x && point.x < window.xMax && window.yMin < point.y && point.y < window.yMax)
    }
    // The fitted exponential is drawn too, and a regression that cannot be worked out is not.
    let curve = Calculator().plotContent("expreg([[0,2],[1,6],[2,18]])")
    #expect(curve.points.count == 3)
    #expect(abs(curve.functions[0].evaluate(3) - 54) < 1e-9)
    #expect(Calculator().plotContent("expreg([[0,-2],[1,6]])").isEmpty)
    #expect(Calculator().plotContent("mean(1,2,3)").isEmpty)
  }

  // MARK: Reports

  @Test("stats reports the five-number summary and more")
  func summaryReport() throws {
    let rows = try report("stats(2, 4, 4, 4, 5, 5, 7, 9)")
    #expect(rows[.count] == [8])
    #expect(rows[.mean] == [5])
    #expect(rows[.sum] == [40])
    #expect(rows[.sumOfSquares] == [232])
    #expect(rows[.populationDeviation] == [2])
    #expect(rows[.sampleDeviation] == [try Expr.fraction(32, 7).raised(to: .fraction(1, 2))])
    #expect(rows[.minimum] == [2])
    #expect(rows[.firstQuartile] == [4])
    #expect(rows[.median] == [.fraction(9, 2)])
    #expect(rows[.thirdQuartile] == [6])
    #expect(rows[.maximum] == [9])
    #expect(rows[.mode] == [4])

    // One datum has no sample deviation; data with no mode leave that row out.
    let single = try report("stats(5)")
    #expect(single[.sampleDeviation] == nil)
    #expect(single[.mode] == [5])
    #expect(try report("stats(1, 2, 3)")[.mode] == nil)
  }

  @Test("linreg reports the line, its correlation and its square")
  func lineReport() throws {
    // The points (1, 2), (2, 4), (3, 5), (4, 4), (5, 5): the textbook line y = 0.6 x + 2.2.
    let rows = try report("linreg([[1,2],[2,4],[3,5],[4,4],[5,5]])")
    #expect(rows[.slope] == [.fraction(3, 5)])
    #expect(rows[.intercept] == [.fraction(11, 5)])
    #expect(rows[.equation] == [Expr.fraction(3, 5) * .symbol("x") + .fraction(11, 5)])
    #expect(rows[.determination] == [.fraction(3, 5)])
    #expect(rows[.count] == [5])
    // r² = 3/5, so r = √(3/5) = √15/5.
    #expect(rows[.correlation] == [try Expr.fraction(3, 5).raised(to: .fraction(1, 2))])
    // A falling line has a negative slope and a negative r: through (1, 5), (2, 3), (3, 2) it is y = −1.5 x + 19/3.
    let falling = try report("linreg([[1,5],[2,3],[3,2]])")
    #expect(falling[.slope] == [.fraction(-3, 2)])
    #expect(falling[.intercept] == [.fraction(19, 3)])
    #expect(falling[.correlation]?.first?.numericSign == -1)
  }

  // MARK: Edges

  @Test("what cannot be worked out says why")
  func errors() throws {
    #expect(failure("stdev(5)") == .math(.insufficientData))
    #expect(failure("variance(1)") == .math(.insufficientData))
    #expect(failure("linreg([[1,2]])") == .math(.insufficientData))
    #expect(failure("slope([[1],[1],[1]], [[1],[2],[3]])") == .math(.degenerateData))
    #expect(failure("corr([[1],[2],[3]], [[5],[5],[5]])") == .math(.degenerateData))
    #expect(failure("mean([[1,2],[3,4]])") == .math(.dimensionMismatch))
    #expect(failure("cov([[1],[2],[3]], [[1],[2]])") == .math(.dimensionMismatch))
    #expect(failure("mean([[1],[2]], [[1],[2],[3]])") == .math(.dimensionMismatch))
    #expect(failure("mean([[1],[2]], [[1/2],[1]])") == .math(.domain))
    #expect(failure("mean([[1],[2]], [[-1],[1]])") == .math(.domain))
    #expect(failure("mean([[1],[2]], [[0],[0]])") == .math(.insufficientData))
    #expect(failure("quartile([[1],[2],[3]], 4)") == .math(.domain))
    #expect(failure("percentile([[1],[2],[3]], 101)") == .math(.domain))
    #expect(failure("percentile([[1],[2],[3]], -1)") == .math(.domain))
    #expect(failure("mean(x, 2)") == .math(.unsupported))
    #expect(failure("mean(i, 2)") == .math(.unsupported))
    #expect(failure("stats(1,2,3) + 1") == .math(.unsupported))
    #expect(failure("2 * linreg([[1,2],[2,3]])") == .math(.unsupported))
    #expect(failure("mean()") != nil)
  }

  @Test("a statistic is a number in a formula")
  func inFormulas() throws {
    #expect(try value("2*mean(1,2,3)+1") == 5)
    #expect(try value("mean(1,2,3)^2") == 4)
    #expect(try value("√varp(2,4,4,4,5,5,7,9)") == (try value("√4")))
    #expect(try value("max(mean(1,3), median(1,2,9))") == 2)
    let letters = try Calculator().compute("D = [[1],[2],[6]]\nmean(D)")
    guard case .lines(let lines) = letters, let last = lines.last, case .scalar(let mean) = last.quantity else {
      Issue.record("not a worksheet")
      return
    }
    #expect(mean == 3)
  }

  @Test("a column of data has up to 200 rows, and the algebra of matrices keeps its limits")
  func sizes() throws {
    let long = (1...200).map { "[\($0)]" }.joined(separator: ",")
    #expect(try value("mean([\(long)])") == .fraction(201, 2))
    #expect(try value("count([\(long)])") == 200)
    let tooLong = (1...201).map { "[\($0)]" }.joined(separator: ",")
    #expect(failure("mean([\(tooLong)])") != nil)
    // A product that would have more than 10 000 entries (200 × 200 here) is not worked out.
    #expect(failure("[\(long)] * [\(long)]^T") == .math(.overflow))
    // The inverse and the determinant are still of square matrices of up to 10.
    #expect(failure("det([\(long)])") == .math(.dimensionMismatch))
    // 100 numbers written out one by one are accepted; 101 are not.
    let hundred = (1...100).map(String.init).joined(separator: ",")
    #expect(try value("count(\(hundred))") == 100)
    #expect(failure("count(\(hundred),101)") != nil)
  }

  @Test("data may be given a letter's value and used again")
  func worksheetData() throws {
    let result = try Calculator().compute("X = [[1],[2],[3],[4]]\nY = [[2],[4],[5],[8]]\nslope(X, Y)")
    guard case .lines(let lines) = result, case .scalar(let slope) = lines.last?.quantity else {
      Issue.record("not a worksheet")
      return
    }
    #expect(slope == .fraction(19, 10))
  }
}
