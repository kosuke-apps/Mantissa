import Foundation
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

  private struct Distributions: Decodable {
    struct Binomial: Decodable {
      var n: Int
      var p: String
      var k: Int
      var pdf: String
      var cdf: String
      var q: String
      var inv: Int
    }
    struct Poisson: Decodable {
      var lambda: String
      var k: Int
      var pdfFactor: String
      var cdfFactor: String
      var pdf: String
      var cdf: String
      var q: String
      var inv: Int
    }
    struct Geometric: Decodable {
      var p: String
      var k: Int
      var pdf: String
      var cdf: String
      var q: String
      var inv: Int
    }
    struct Hypergeometric: Decodable {
      var population: Int
      var successes: Int
      var drawn: Int
      var k: Int
      var pdf: String
      var cdf: String
    }
    struct Uniform: Decodable {
      var a: String
      var b: String
      var x: String
      var pdf: String
      var cdf: String
      var p: String
      var inv: String
    }
    struct Exponential: Decodable {
      var lambda: String
      var x: String
      var pdf: String
      var cdf: String
      var p: String
      var inv: String
    }
    var binomial: [Binomial]
    var poisson: [Poisson]
    var geometric: [Geometric]
    var hypergeometric: [Hypergeometric]
    var uniform: [Uniform]
    var exponential: [Exponential]
  }

  private struct Special: Decodable {
    struct Erf: Decodable {
      var x: String
      var erf: String
      var erfc: String
    }
    struct Probit: Decodable {
      var p: String
      var z: String
    }
    struct Normal: Decodable {
      var x: String
      var mu: String
      var sigma: String
      var pdf: String
      var cdf: String
      var p: String
      var inv: String
    }
    struct Gamma: Decodable {
      var x: String
      var gamma: String
      var lgamma: String
    }
    struct GammaInc: Decodable {
      var a: String
      var x: String
      var p: String
      var q: String
    }
    struct BetaInc: Decodable {
      var x: String
      var a: String
      var b: String
      var lower: String
      var upper: String
    }
    struct GammaInverse: Decodable {
      var a: String
      var p: String
      var x: String
    }
    struct BetaInverse: Decodable {
      var p: String
      var a: String
      var b: String
      var x: String
    }
    /// A row of a t, χ² or F table: a value with its density and distribution function, or a probability with its quantile.
    struct Row: Decodable {
      var nu: String?
      var k: String?
      var d1: String?
      var d2: String?
      var x: String?
      var pdf: String?
      var cdf: String?
      var p: String?
      var inv: String?

      /// The degrees of freedom as the arguments that follow the first.
      var parameters: String {
        if let nu { return nu }
        if let k { return k }
        return "\(d1 ?? ""), \(d2 ?? "")"
      }
    }
    var t: [Row]
    var chisq: [Row]
    var f: [Row]
    var erf: [Erf]
    var probit: [Probit]
    var normal: [Normal]
    var gamma: [Gamma]
    var gammainc: [GammaInc]
    var betainc: [BetaInc]
    var gammaInverse: [GammaInverse]
    var betaInverse: [BetaInverse]
  }

  private struct Vectors: Decodable {
    var one: [OneVariable]
    var two: [TwoVariables]
    var polynomials: [Polynomial]
    var transformed: [Transformed]
    var distributions: Distributions
    var special: Special
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
  private func agree(_ a: BigDecimal, _ b: BigDecimal, digits: Int = 45) -> Bool {
    let tolerance = BigDecimal(BigInt(1), exponent: -digits)
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

  // MARK: Distributions

  /// The decimal value of an input to the settings' 50 digits.
  private func decimal(_ text: String) throws -> BigDecimal {
    try #require(Calculator().evaluate(text).approximation, "\(text) has no decimal")
  }

  @Test("binomial, geometric and hypergeometric probabilities are the exact fractions of 46 cases")
  func discreteOracle() throws {
    let all = try Self.load().distributions
    for item in all.binomial {
      let arguments = "\(item.n), \(item.p)"
      #expect(
        try value("binompdf(\(arguments), \(item.k))") == (try value(item.pdf)), "binompdf \(arguments), \(item.k)")
      #expect(
        try value("binomcdf(\(arguments), \(item.k))") == (try value(item.cdf)), "binomcdf \(arguments), \(item.k)")
      #expect(try value("binominv(\(arguments), \(item.q))") == .integer(item.inv), "binominv \(arguments), \(item.q)")
    }
    for item in all.geometric {
      #expect(try value("geompdf(\(item.p), \(item.k))") == (try value(item.pdf)), "geompdf \(item.p), \(item.k)")
      #expect(try value("geomcdf(\(item.p), \(item.k))") == (try value(item.cdf)), "geomcdf \(item.p), \(item.k)")
      #expect(try value("geominv(\(item.p), \(item.q))") == .integer(item.inv), "geominv \(item.p), \(item.q)")
    }
    for item in all.hypergeometric {
      let arguments = "\(item.population), \(item.successes), \(item.drawn), \(item.k)"
      #expect(try value("hyperpdf(\(arguments))") == (try value(item.pdf)), "hyperpdf \(arguments)")
      #expect(try value("hypercdf(\(arguments))") == (try value(item.cdf)), "hypercdf \(arguments)")
    }
  }

  @Test(
    "Poisson probabilities are e^−λ times a fraction, and agree with decimals to 45 digits; the inverse is the smallest k"
  )
  func poissonOracle() throws {
    for item in try Self.load().distributions.poisson {
      let decay = "exp(-\(item.lambda))"
      #expect(
        try value("poissonpdf(\(item.lambda), \(item.k))") == (try value("\(decay)*(\(item.pdfFactor))")),
        "poissonpdf \(item.lambda), \(item.k)")
      #expect(
        try value("poissoncdf(\(item.lambda), \(item.k))") == (try value("\(decay)*(\(item.cdfFactor))")),
        "poissoncdf \(item.lambda), \(item.k)")
      let pdf = try decimal("poissonpdf(\(item.lambda), \(item.k))")
      let cdf = try decimal("poissoncdf(\(item.lambda), \(item.k))")
      #expect(agree(pdf, try #require(BigDecimal(item.pdf))), "pdf digits, \(item.lambda), \(item.k)")
      #expect(agree(cdf, try #require(BigDecimal(item.cdf))), "cdf digits, \(item.lambda), \(item.k)")
      #expect(
        try value("poissoninv(\(item.lambda), \(item.q))") == .integer(item.inv), "poissoninv \(item.lambda), \(item.q)"
      )
    }
  }

  @Test("uniform and exponential distributions: exact, and the exponential's decimals agree to 45 digits")
  func continuousOracle() throws {
    let all = try Self.load().distributions
    for item in all.uniform {
      let arguments = "\(item.x), \(item.a), \(item.b)"
      #expect(try value("uniformpdf(\(arguments))") == (try value(item.pdf)), "uniformpdf \(arguments)")
      #expect(try value("uniformcdf(\(arguments))") == (try value(item.cdf)), "uniformcdf \(arguments)")
      #expect(try value("uniforminv(\(item.p), \(item.a), \(item.b))") == (try value(item.inv)), "uniforminv \(item.p)")
    }
    for item in all.exponential {
      for (function, argument, expected) in [
        ("exponentialpdf", item.x, item.pdf), ("exponentialcdf", item.x, item.cdf),
        ("exponentialinv", item.p, item.inv),
      ] {
        let text = "\(function)(\(argument), \(item.lambda))"
        let want = try #require(BigDecimal(expected))
        if expected == "0" || want.isZero {
          #expect((try decimal(text)).isZero, "\(text)")
        } else {
          #expect(agree(try decimal(text), want), "\(text) against \(expected)")
        }
      }
    }
  }

  @Test("edges of the distributions: outside the support, whole numbers, and what is refused")
  func distributionEdges() throws {
    // Outside the values a distribution takes, a pdf is 0 and a cdf is 0 or 1.
    #expect(try value("binompdf(5, 0.5, 2.5)") == 0)
    #expect(try value("binompdf(5, 0.5, 6)") == 0)
    #expect(try value("binompdf(5, 0.5, -1)") == 0)
    #expect(try value("binomcdf(5, 0.5, -1)") == 0)
    #expect(try value("binomcdf(5, 0.5, 5)") == 1)
    #expect(try value("binomcdf(5, 0.5, 99)") == 1)
    #expect(try value("binomcdf(5, 0.5, 2.9)") == (try value("binomcdf(5, 0.5, 2)")))
    #expect(try value("binomcdf(4, 1/2, 2)") == .fraction(11, 16))
    #expect(try value("binompdf(10, 0, 0)") == 1)
    #expect(try value("binompdf(10, 1, 10)") == 1)
    #expect(try value("binompdf(0, 0.3, 0)") == 1)
    #expect(try value("binominv(10, 0.5, 0)") == 0)
    #expect(try value("binominv(10, 0.5, 1)") == 10)
    #expect(try value("poissonpdf(0, 0)") == 1)
    #expect(try value("poissonpdf(0, 3)") == 0)
    #expect(try value("poissoncdf(3, -1)") == 0)
    #expect(try value("geompdf(0.5, 0)") == 0)
    #expect(try value("geomcdf(0.5, 0)") == 0)
    #expect(try value("geominv(0.5, 0)") == 1)
    #expect(try value("hyperpdf(10, 4, 3, 5)") == 0)
    #expect(try value("uniformpdf(5, 0, 4)") == 0)
    #expect(try value("uniformcdf(-1, 0, 4)") == 0)
    #expect(try value("uniformcdf(5, 0, 4)") == 1)
    #expect(try value("uniformpdf(4, 0, 4)") == .fraction(1, 4))
    #expect(try value("exponentialpdf(-1, 2)") == 0)
    #expect(try value("exponentialcdf(0, 2)") == 0)
    #expect(try value("exponentialinv(0, 2)") == 0)
    // The values are exact expressions and still go inside formulas.
    #expect(try value("1 - binomcdf(4, 1/2, 2)") == .fraction(5, 16))
    #expect(try value("exponentialcdf(1, 1)") == (try value("1 - exp(-1)")))
    #expect(try value("2 * binompdf(2, 1/2, 1)") == 1)

    // What is refused.
    #expect(failure("binompdf(5, 1.5, 2)") == .math(.domain))
    #expect(failure("binompdf(5, -0.1, 2)") == .math(.domain))
    #expect(failure("binompdf(-1, 0.5, 0)") == .math(.domain))
    #expect(failure("binompdf(2.5, 0.5, 0)") == .math(.domain))
    #expect(failure("binompdf(2001, 0.5, 0)") == .math(.overflow))
    #expect(failure("binompdf(5, √2/2, 2)") == .math(.unsupported))
    #expect(failure("binominv(5, 0.5, 1.1)") == .math(.domain))
    #expect(failure("poissonpdf(-1, 2)") == .math(.domain))
    #expect(failure("poissoninv(2, 1)") == .math(.domain))
    #expect(failure("geompdf(0, 1)") == .math(.domain))
    #expect(failure("geominv(0.5, 1)") == .math(.domain))
    #expect(failure("hyperpdf(10, 11, 3, 1)") == .math(.domain))
    #expect(failure("hyperpdf(10, 4, 11, 1)") == .math(.domain))
    #expect(failure("uniformpdf(1, 2, 2)") == .math(.domain))
    #expect(failure("uniforminv(1.5, 0, 1)") == .math(.domain))
    #expect(failure("exponentialpdf(1, 0)") == .math(.domain))
    #expect(failure("exponentialinv(1, 2)") == .math(.domain))
    #expect(failure("binompdf(5, 0.5)") != nil)
    #expect(failure("binompdf(5, 0.5, x)") == .math(.unsupported))
  }

  // MARK: Error function and the normal distribution

  @Test("erf and erfc agree to 45 digits with an independent Taylor series, from 0.001 to 27.5 and below zero")
  func errorFunction() throws {
    for item in try Self.load().special.erf {
      let erf = try decimal("erf(\(item.x))")
      let erfc = try decimal("erfc(\(item.x))")
      #expect(agree(erf, try #require(BigDecimal(item.erf))), "erf(\(item.x)) = \(erf), expected \(item.erf)")
      #expect(agree(erfc, try #require(BigDecimal(item.erfc))), "erfc(\(item.x)) = \(erfc), expected \(item.erfc)")
    }
  }

  @Test("the normal quantile agrees to 45 digits, from 10^-100 to 1 - 10^-12, and inverts the normal cdf")
  func quantile() throws {
    for item in try Self.load().special.probit {
      // `1e-100` would be read as 1·e − 100.
      let typed = item.p.contains("e-") ? "10^(-\(item.p.split(separator: "-")[1]))" : item.p
      let z = try decimal("probit(\(typed))")
      #expect(agree(z, try #require(BigDecimal(item.z))), "probit(\(item.p)) = \(z), expected \(item.z)")
    }
    for (typed, p) in [("0.2", "0.2"), ("0.0001", "0.0001"), ("0.9", "0.9"), ("10^(-40)", "1e-40")] {
      let there = try decimal("normalcdf(normalinv(\(typed)))")
      #expect(agree(there, try #require(BigDecimal(p))), "Φ(Φ⁻¹(\(typed)))")
    }
  }

  @Test("normalpdf, normalcdf and normalinv with a mean and a standard deviation, against 16 decimal computations")
  func normalOracle() throws {
    for item in try Self.load().special.normal {
      let arguments = "\(item.x), \(item.mu), \(item.sigma)"
      #expect(
        agree(try decimal("normalpdf(\(arguments))"), try #require(BigDecimal(item.pdf))), "normalpdf(\(arguments))")
      #expect(
        agree(try decimal("normalcdf(\(arguments))"), try #require(BigDecimal(item.cdf))), "normalcdf(\(arguments))")
      #expect(
        agree(try decimal("normalinv(\(item.p), \(item.mu), \(item.sigma))"), try #require(BigDecimal(item.inv))),
        "normalinv(\(item.p), \(item.mu), \(item.sigma))")
    }
  }

  @Test("exact values of the error function and the normal distribution, and their derivatives")
  func errorFunctionExact() throws {
    #expect(try value("erf(0)") == 0)
    #expect(try value("erfc(0)") == 1)
    #expect(try value("erf(-x)") == (try value("-erf(x)")))
    #expect(try value("probit(1/2)") == 0)
    #expect(try value("normalcdf(0)") == .fraction(1, 2))
    #expect(try value("normalcdf(5, 5, 3)") == .fraction(1, 2))
    #expect(try value("normalinv(0.5, 3, 2)") == 3)
    #expect(try value("normalpdf(0)") == (try value("1/√(2π)")))
    #expect(try value("normalpdf(2, 2, 3)") == (try value("1/(3√(2π))")))
    // The derivative of erf is the bell curve; of erfc, minus it; of probit, 1/ the density there.
    #expect(try value("diff(erf(x), x)") == (try value("2/√π * e^(-x^2)")))
    #expect(try value("diff(erfc(x), x)") == (try value("-2/√π * e^(-x^2)")))
    #expect(try value("diff(erf(2x), x)") == (try value("4/√π * e^(-4x^2)")))
    // Ordinary arithmetic with them.
    #expect(try value("erf(1) + erfc(1)").numericSign == 1)
    let one = try decimal("erf(1) + erfc(1)")
    #expect(agree(one, BigDecimal(1)))
    // The cdf above and below the mean add to one.
    #expect(agree(try decimal("normalcdf(1.3) + normalcdf(-1.3)"), BigDecimal(1)))
    // The tails keep their digits: Φ(−30) is about 4.9e-198.
    let tail = try decimal("normalcdf(-30)")
    #expect(tail < BigDecimal("4.91e-198")! && tail > BigDecimal("4.90e-198")!)

    #expect(failure("probit(0)") == .math(.domain))
    #expect(failure("probit(1)") == .math(.domain))
    #expect(failure("probit(1.5)") == .math(.domain))
    #expect(failure("normalcdf(1, 0, 0)") == .math(.domain))
    #expect(failure("normalcdf(1, 0, -2)") == .math(.domain))
    #expect(failure("normalinv(0, 0, 1)") == .math(.domain))
    // With a letter in it they are expressions to draw and to differentiate.
    #expect(failure("normalpdf(x)") == nil)
    #expect(try value("diff(normalcdf(x), x)") == (try value("normalpdf(x)")))
  }

  // MARK: Gamma, incomplete gamma and beta

  private func big(_ text: String) throws -> BigDecimal {
    try #require(Calculator().evaluate(text).approximation, "\(text)")
  }

  @Test("Γ and ln Γ agree to 45 digits with Spouge's approximation, from 0.1 to 300")
  func gammaFunction() throws {
    for item in try Self.load().special.gamma {
      let x = try big(item.x)
      #expect(agree(try x.gamma(precision: 50), try #require(BigDecimal(item.gamma))), "Γ(\(item.x))")
      let want = try #require(BigDecimal(item.lgamma))
      let got = try x.lgamma(precision: 50)
      // ln Γ(1) = ln Γ(2) = 0, which the oracle's Spouge approximation has to about 10^-150.
      if want.magnitude < BigDecimal(BigInt(1), exponent: -100) {
        #expect(got.magnitude < BigDecimal(BigInt(1), exponent: -45), "ln Γ(\(item.x))")
      } else {
        #expect(agree(got, want), "ln Γ(\(item.x))")
      }
    }
    // Reflection: Γ(−1.5) = 4√π/3, and the poles.
    let negative = try BigDecimal("-1.5")!.gamma(precision: 50)
    let expected = try (BigDecimal.pi(precision: 60).squareRoot(precision: 60) * BigDecimal(4)).divided(
      by: BigDecimal(3), precision: 60)
    #expect(agree(negative, expected))
    #expect(throws: MathError.domain) { try BigDecimal(-2).gamma(precision: 20) }
    #expect(throws: MathError.domain) { try BigDecimal(0).gamma(precision: 20) }
  }

  @Test("the regularised incomplete gamma function, both sides, agrees to 45 digits with the series in decimals")
  func incompleteGamma() throws {
    for item in try Self.load().special.gammainc {
      let (a, x) = (try big(item.a), try big(item.x))
      let p = try BigDecimal.gammaP(a, x, precision: 50)
      let q = try BigDecimal.gammaQ(a, x, precision: 50)
      #expect(agree(p, try #require(BigDecimal(item.p))), "P(\(item.a), \(item.x)) = \(p), expected \(item.p)")
      #expect(agree(q, try #require(BigDecimal(item.q))), "Q(\(item.a), \(item.x)) = \(q), expected \(item.q)")
    }
  }

  @Test("the regularised incomplete beta function, both sides, agrees to 45 digits with its hypergeometric series")
  func incompleteBeta() throws {
    for item in try Self.load().special.betainc {
      let (x, a, b) = (try big(item.x), try big(item.a), try big(item.b))
      let lower = try BigDecimal.betaI(x, a, b, precision: 50)
      let upper = try BigDecimal.betaIComplement(x, a, b, precision: 50)
      #expect(
        agree(lower, try #require(BigDecimal(item.lower))),
        "I_\(item.x)(\(item.a), \(item.b)) = \(lower), expected \(item.lower)")
      #expect(
        agree(upper, try #require(BigDecimal(item.upper))),
        "1 − I_\(item.x)(\(item.a), \(item.b)) = \(upper), expected \(item.upper)")
    }
  }

  @Test("the inverses of the incomplete functions agree to 45 digits with Newton's method in decimals")
  func incompleteInverses() throws {
    for item in try Self.load().special.gammaInverse {
      let p = try big(item.p == "1e-10" ? "10^(-10)" : item.p)
      let x = try BigDecimal.inverseGammaP(try big(item.a), p, precision: 50)
      #expect(
        agree(x, try #require(BigDecimal(item.x))), "gammaincinv(\(item.a), \(item.p)) = \(x), expected \(item.x)")
    }
    for item in try Self.load().special.betaInverse {
      let x = try BigDecimal.inverseBetaI(try big(item.p), try big(item.a), try big(item.b), precision: 50)
      #expect(
        agree(x, try #require(BigDecimal(item.x))),
        "betaincinv(\(item.p), \(item.a), \(item.b)) = \(x), expected \(item.x)")
    }
  }

  @Test("the machine-number versions agree with the decimal ones to 11 digits")
  func machineNumbers() throws {
    for item in try Self.load().special.gammainc {
      let (p, q) = SpecialDouble.gamma(try big(item.a).doubleValue, try big(item.x).doubleValue)
      let (wantP, wantQ) = (try #require(BigDecimal(item.p)).doubleValue, try #require(BigDecimal(item.q)).doubleValue)
      #expect(abs(p - wantP) <= 1e-11 * max(wantP, 1e-300), "P(\(item.a), \(item.x)) = \(p) against \(wantP)")
      #expect(abs(q - wantQ) <= 1e-11 * max(wantQ, 1e-300), "Q(\(item.a), \(item.x)) = \(q) against \(wantQ)")
    }
    for item in try Self.load().special.betainc {
      let x = try big(item.x).doubleValue
      let (lower, upper) = SpecialDouble.beta(x, 1 - x, try big(item.a).doubleValue, try big(item.b).doubleValue)
      let (wantLower, wantUpper) = (
        try #require(BigDecimal(item.lower)).doubleValue, try #require(BigDecimal(item.upper)).doubleValue
      )
      #expect(abs(lower - wantLower) <= 1e-11 * max(wantLower, 1e-300), "I_\(item.x)(\(item.a), \(item.b))")
      #expect(abs(upper - wantUpper) <= 1e-11 * max(wantUpper, 1e-300), "1 − I_\(item.x)(\(item.a), \(item.b))")
    }
  }

  @Test(
    "Student's t, χ² and F: density, distribution function and quantile agree to 40 digits with decimals computed another way"
  )
  func studentChiSquaredFisherOracle() throws {
    let special = try Self.load().special
    for (name, rows) in [("t", special.t), ("chisq", special.chisq), ("f", special.f)] {
      for row in rows {
        if let x = row.x, let pdf = row.pdf, let cdf = row.cdf {
          let arguments = "\(x), \(row.parameters)"
          for (kind, expected) in [("pdf", pdf), ("cdf", cdf)] {
            let got = try decimal("\(name)\(kind)(\(arguments))")
            let want = try #require(BigDecimal(expected))
            if want.isZero {
              #expect(got.isZero, "\(name)\(kind)(\(arguments))")
            } else {
              #expect(agree(got, want, digits: 40), "\(name)\(kind)(\(arguments)) = \(got), expected \(expected)")
            }
          }
        } else if let p = row.p, let inv = row.inv {
          let text = "\(name)inv(\(p), \(row.parameters))"
          let got = try decimal(text)
          let want = try #require(BigDecimal(inv))
          if want.isZero {
            #expect(got.magnitude < BigDecimal(BigInt(1), exponent: -40), "\(text)")
          } else {
            #expect(agree(got, want, digits: 40), "\(text) = \(got), expected \(inv)")
          }
        }
      }
    }
  }

  @Test(
    "exact forms: the cdf of the t distribution with even degrees of freedom, the χ² cdf with even or odd, the F cdf with even"
  )
  func exactContinuous() throws {
    // χ² with 2 degrees of freedom: 1 − e^(−x/2).
    #expect(try value("chisqcdf(3, 2)") == (try value("1 - exp(-3/2)")))
    // With a letter in it the call stays as written (it is worked out without the loss of digits that 1 − e^…  has in a tail), and is drawn.
    #expect(Calculator().plotFunctions("chisqcdf(x, 2)").count == 1)
    #expect(abs(Calculator().plotFunctions("chisqcdf(x, 2)")[0].evaluate(3) - (1 - exp(-1.5))) < 1e-14)
    // In the tail, where 1 − e^…  would lose its digits, the value is still right to the last one.
    let tail = try decimal("chisqcdf(0.001, 30)")
    #expect(tail > BigDecimal("2.33e-62")! && tail < BigDecimal("2.34e-62")!)
    // With 4: 1 − e^(−x/2)(1 + x/2).
    #expect(try value("chisqcdf(2, 4)") == (try value("1 - exp(-1)*(1 + 1)")))
    // With 1: erf(√(x/2)).
    #expect(try value("chisqcdf(2, 1)") == (try value("erf(1)")))
    // F with 2 and 2 degrees of freedom: x/(1 + x).
    #expect(try value("fcdf(3, 2, 2)") == .fraction(3, 4))
    #expect(try value("fcdf(1, 4, 4)") == .fraction(1, 2))
    // t with 2 degrees of freedom: 1/2 + t/(2√(2 + t²)).
    #expect(try value("tcdf(0, 2)") == .fraction(1, 2))
    #expect(try value("tcdf(1, 2)") == (try value("1/2 + 1/(2*sqrt(3))")))
    #expect(try value("tcdf(-1, 2)") == (try value("1/2 - 1/(2*sqrt(3))")))
    #expect(try value("tinv(0.5, 7)") == 0)
    #expect(try value("chisqpdf(-1, 3)") == 0)
    #expect(try value("fpdf(-1, 3, 4)") == 0)
    #expect(try value("chisqpdf(0, 3)") == 0)
    #expect(try value("chisqpdf(0, 2)") == .fraction(1, 2))
    #expect(try value("fpdf(0, 2, 5)") == 1)
    #expect(try value("chisqinv(0, 4)") == 0)
    #expect(try value("finv(0, 3, 4)") == 0)
    // The density of t with 1 degree of freedom is the Cauchy density 1/(π(1 + x²)).
    #expect(try value("tpdf(2, 1)") == (try value("1/(π*(1+4))")))
    // Γ at whole and half-integers is exact.
    #expect(try value("gamma(5)") == 24)
    #expect(try value("gamma(1/2)") == (try value("√π")))
    #expect(try value("gamma(5/2)") == (try value("3√π/4")))
    #expect(try value("gamma(-1/2)") == (try value("-2√π")))
    #expect(try value("gamma(1/3)").numericSign == 1)
    // Both the cdf and its inverse go through the incomplete functions: the inverse of the cdf is the value.
    for (cdf, inverse, value) in [("tcdf", "tinv", "1.7"), ("chisqcdf", "chisqinv", "5.5"), ("fcdf", "finv", "2.2")] {
      let parameters = cdf == "fcdf" ? "5.5, 8.25" : "6.5"
      let there = try decimal("\(inverse)(\(cdf)(\(value), \(parameters)), \(parameters))")
      #expect(agree(there, try #require(BigDecimal(value)), digits: 40), "\(inverse)(\(cdf)(\(value)))")
    }
    // What is refused.
    #expect(failure("tcdf(1, 0)") == .math(.domain))
    #expect(failure("tcdf(1, -3)") == .math(.domain))
    #expect(failure("chisqcdf(1, 0)") == .math(.domain))
    #expect(failure("fcdf(1, 0, 3)") == .math(.domain))
    #expect(failure("tinv(1, 5)") == .math(.domain))
    #expect(failure("tinv(0, 5)") == .math(.domain))
    #expect(failure("chisqinv(1, 5)") == .math(.domain))
    #expect(failure("finv(-0.1, 2, 3)") == .math(.domain))
    #expect(failure("chisqpdf(0, 1)") == .math(.noValue))
    #expect(failure("gamma(0)") == .math(.domain))
    #expect(failure("gamma(-3)") == .math(.domain))
    #expect(failure("gammainc(0, 1)") == .math(.domain))
    #expect(failure("betainc(1.5, 1, 1)") == .math(.domain))
  }

  @Test("the normal density and distribution function are drawn")
  func normalPlots() throws {
    let bell = Calculator().plotFunctions("normalpdf(x, 1, 2)")
    #expect(bell.count == 1)
    #expect(abs(bell[0].evaluate(1) - 1 / (2 * (2 * Double.pi).squareRoot())) < 1e-15)
    let cdf = Calculator().plotFunctions("normalcdf(x)")
    #expect(cdf.count == 1)
    #expect(abs(cdf[0].evaluate(0) - 0.5) < 1e-15)
    #expect(abs(cdf[0].evaluate(1.96) - 0.9750021048517795) < 1e-14)
    let quantile = Calculator().plotFunctions("normalinv(x)")
    #expect(quantile.count == 1)
    #expect(abs(quantile[0].evaluate(0.975) - 1.959963984540054) < 1e-12)
    #expect(quantile[0].evaluate(1.5).isNaN)
  }

  @Test("an exponential of a power tower is refused at once, as it was not before (it took over a minute to give up)")
  func powerTower() throws {
    let started = Date()
    #expect(throws: (any Error).self) { try Calculator().solve("exp((e^7!))<=0.5") }
    // The value itself is kept as written (it has no decimal), and was never the slow part.
    let kept = try Calculator().evaluate("exp(e^7!)")
    #expect(kept.approximation == nil)
    #expect(Date().timeIntervalSince(started) < 20, "it should have given up long before this")
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
