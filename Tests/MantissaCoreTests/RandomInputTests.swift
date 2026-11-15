import Foundation
import Testing

@testable import MantissaCore

/// Random text goes through everything the app does with an input, to find what crashes, runs out of memory or never ends.
/// Such inputs were found this way (an absolute value of something undefined that sent the solver round in circles, the
/// divisors of 100!); the cases the fuzzing found are pinned in the suites of the code they concerned, and this keeps looking.
/// `MANTISSA_SEED=n` changes the sequence and `MANTISSA_SAMPLES=n` the number of inputs.
@Suite("Random inputs")
struct RandomInputTests {
  private static let atoms = [
    "x", "y", "2", "3", "0", "1", "10", "0.5", "π", "e", "i", "7", "100", "1/2", "∞", "a",
    // Matrices and vectors, so that they meet every operator and function.
    "[[1,2],[3,4]]", "[[x,1],[0,y]]", "[[1],[2],[3]]", "[[0,0],[0,0]]", "[[a,b,c]]",
  ]
  private static let functions = [
    "sin", "cos", "tan", "ln", "log", "sqrt", "abs", "asin", "atan", "exp", "cbrt", "sinh", "cosh", "floor", "sign",
    "acos",
    "re", "im", "conj",
    "det", "inverse", "transpose", "trace", "rank", "rref", "norm", "identity",
  ]
  private static let matrices = [
    "[[1,2],[3,4]]", "[[x,1],[0,y]]", "[[1],[2],[3]]", "[[0,0],[0,0]]", "[[a,b,c]]", "[[2,0],[0,2]]",
  ]
  /// Statistics (of numbers, vectors and tables) and distributions, with the number of arguments each takes.
  private static let statistics: [(name: String, arguments: ClosedRange<Int>)] = [
    ("mean", 1...4), ("median", 1...4), ("mode", 1...4), ("variance", 1...4), ("stdev", 1...4), ("varp", 1...3),
    ("sort", 1...3), ("count", 1...3), ("total", 1...3), ("iqr", 1...4), ("range", 1...3), ("min", 1...3),
    ("max", 1...3),
    ("quartile", 2...2), ("percentile", 2...2), ("cov", 1...2), ("corr", 1...2), ("slope", 1...2), ("intercept", 1...2),
    ("stats", 1...4), ("linreg", 1...2), ("polyreg", 2...3), ("expreg", 1...2), ("powreg", 1...2), ("logreg", 1...2),
  ]
  private static let distributions: [(name: String, arguments: Int)] = [
    ("binompdf", 3), ("binomcdf", 3), ("binominv", 3), ("poissonpdf", 2), ("poissoncdf", 2), ("poissoninv", 2),
    ("geompdf", 2), ("geomcdf", 2), ("geominv", 2), ("hyperpdf", 4), ("hypercdf", 4), ("uniformpdf", 3),
    ("uniformcdf", 3),
    ("uniforminv", 3), ("exponentialpdf", 2), ("exponentialcdf", 2), ("exponentialinv", 2), ("normalpdf", 3),
    ("normalcdf", 3), ("normalinv", 3), ("erf", 1), ("erfc", 1), ("probit", 1), ("tpdf", 2), ("tcdf", 2), ("tinv", 2),
    ("chisqpdf", 2), ("chisqcdf", 2), ("chisqinv", 2), ("fpdf", 3), ("fcdf", 3), ("finv", 3), ("gamma", 1), ("beta", 2),
    ("gammainc", 2), ("gammaincinv", 2), ("betainc", 3), ("betaincinv", 3),
  ]
  /// Numbers for the arguments of a distribution: small, so that a random input does not ask for a sum of a million terms.
  private static let distributionAtoms = [
    "x", "2", "3", "0.5", "1/2", "10", "7", "0", "1", "-1", "0.9", "a", "√2", "5",
  ]
  private static let tables = [
    "[[1],[2],[3],[4]]", "[[1,2],[2,3],[3,5]]", "[[1],[1],[1]]", "[[1,2],[1,3],[1,5]]", "[[0,1],[1,2],[2,4],[3,8]]",
    "[[x],[2],[3]]", "[[1,0],[2,0],[3,0]]",
  ]
  private static let operators = ["+", "-", "*", "/", "^"]
  private static let relations = ["=", "<", ">", "<=", ">=", "≠"]

  private struct Writer {
    var generator: SplitMix64

    mutating func pick<T>(_ list: [T]) -> T { list[Int(generator.next() % UInt64(list.count))] }

    mutating func expression(_ depth: Int) -> String {
      if depth == 0 || generator.next() % 5 == 0 { return pick(RandomInputTests.atoms) }
      switch generator.next() % 9 {
      case 0, 1, 2:
        return "(" + expression(depth - 1) + pick(RandomInputTests.operators) + expression(depth - 1) + ")"
      case 3, 4: return pick(RandomInputTests.functions) + "(" + expression(depth - 1) + ")"
      case 5: return expression(depth - 1) + "!"
      case 6:
        switch generator.next() % 4 {
        case 0: return "int(" + expression(depth - 1) + ",x)"
        case 1: return "diff(" + expression(depth - 1) + ",x)"
        case 2: return "lim(" + expression(depth - 1) + ",x," + pick(RandomInputTests.atoms) + ")"
        default: return "sum(" + expression(depth - 1) + ",k,1," + pick(["5", "n", "∞", "50"]) + ")"
        }
      case 7:
        if generator.next() % 3 == 0 { return statisticsCall() }
        return pick(["dot", "cross"]) + "(" + expression(depth - 1) + "," + expression(depth - 1) + ")"
      default: return pick(["+", "-"]) + expression(depth - 1)
      }
    }

    /// A statistic of some numbers or a table, or a distribution of some numbers.
    mutating func statisticsCall() -> String {
      if generator.next() % 2 == 0 {
        let item = pick(RandomInputTests.statistics)
        let count = item.arguments.lowerBound + Int(generator.next() % UInt64(item.arguments.count))
        let data = (0..<count).map { _ in
          generator.next() % 2 == 0 ? pick(RandomInputTests.tables) : pick(RandomInputTests.atoms)
        }
        return item.name + "(" + data.joined(separator: ",") + ")"
      }
      let item = pick(RandomInputTests.distributions)
      return item.name + "("
        + (0..<item.arguments).map { _ in pick(RandomInputTests.distributionAtoms) }.joined(separator: ",") + ")"
    }

    mutating func statement() -> String {
      switch generator.next() % 7 {
      case 0, 1: return expression(3) + pick(RandomInputTests.relations) + expression(3)
      case 2: return expression(3) + "=" + expression(2) + "\n" + expression(3) + "=" + expression(2)
      // Letters given matrices, and an equation or an expression to work out from them.
      case 3:
        return "A=" + pick(RandomInputTests.matrices) + "\nB=" + pick(RandomInputTests.matrices) + "\n"
          + pick(["A", "B", "X", "a", "x"]) + pick(["", "*", "+", "-"]) + pick(["A", "B", "X", "(A+B)", "A^2", "A^T"])
          + "="
          + pick(["B", "A", "X", "A*B", "[[1,2],[3,4]]", "A^(-1)"])
      case 4: return statisticsCall()
      default: return expression(4)
      }
    }
  }

  @Test("Whatever is typed, the app gets an answer or an error back, and not too slowly")
  func everythingTheAppDoes() {
    let count = Int(ProcessInfo.processInfo.environment["MANTISSA_SAMPLES"] ?? "") ?? 400
    let limit = Self.limit
    var writer = Writer(generator: SplitMix64(seed: 4242 &+ propertySeedOffset &* 7919))
    let calculator = Calculator()
    var slow: [String] = []
    for _ in 0..<count {
      let text = writer.statement()
      // `MANTISSA_LOG=path` keeps the input being worked on, to see which one it was when the test dies.
      if let path = ProcessInfo.processInfo.environment["MANTISSA_LOG"] {
        try? text.write(toFile: path, atomically: false, encoding: .utf8)
      }
      let started = Self.cpuSeconds()
      do {
        switch try calculator.compute(text) {
        case .number(let evaluation):
          _ = evaluation.otherForms
          _ = Typesetter.nodes(for: evaluation.exact).parserText
        case .matrix(let matrix):
          let nodes = Typesetter.nodes(for: matrix)
          _ = nodes.parserText
          _ = nodes.plainText
          _ = matrix.approximations(precision: 20)
        case .lines(let lines):
          for line in lines {
            switch line.quantity {
            case .scalar(let number): _ = Typesetter.nodes(for: number).plainText
            case .matrix(let matrix): _ = Typesetter.nodes(for: matrix).plainText
            case .report(let report):
              for row in report.rows { for value in row.values { _ = Typesetter.nodes(for: value).plainText } }
            }
          }
        case .report(let report):
          for row in report.rows { for value in row.values { _ = Typesetter.nodes(for: value).plainText } }
        }
      } catch {
        if case .unsupported = error { _ = try? calculator.solve(text) }
      }
      let content = calculator.plotContent(text)
      if !content.isEmpty {
        let window = PlotViewport.fit(content)
        _ = PlotAnalysis.points(of: content.functions, from: window.xMin, to: window.xMax, samples: 400)
        for function in content.functions { _ = PlotSampler.segments(of: function, in: window, count: 200) }
        for relation in content.relations {
          _ = PlotSampler.contourLines(of: relation, in: window, columns: 40, rows: 60)
        }
      }
      if Self.cpuSeconds() - started > limit { slow.append(text.replacingOccurrences(of: "\n", with: " ; ")) }
    }
    #expect(slow.isEmpty, "took over \(limit) s of processor time: \(slow)")
  }

  /// The processor time this thread has used, which does not grow when the machine, or another test running beside this one,
  /// is busy. The test is not asynchronous, so all its work is on one thread.
  private static func cpuSeconds() -> Double {
    var time = timespec()
    clock_gettime(CLOCK_THREAD_CPUTIME_ID, &time)
    return Double(time.tv_sec) + Double(time.tv_nsec) / 1e9
  }

  /// How long one input may take, in seconds of processor time. The tests run unoptimised, which is several times slower than the
  /// app, and under a sanitizer, with the rest of the suite running beside it, slower again (an input that takes 6 s here took 80 s
  /// of processor time there); what this looks for is an input that never ends. `MANTISSA_TIME_LIMIT=n` sets it.
  private static var limit: Double {
    if let text = ProcessInfo.processInfo.environment["MANTISSA_TIME_LIMIT"], let seconds = Double(text) {
      return seconds
    }
    return runsUnderSanitizer ? 200 : 20
  }

  /// Whether a sanitizer runtime is loaded into this process, found by looking for a symbol only it has; the environment
  /// variable Xcode sets for its own runs is not there when `swift test --sanitize=…` runs the tests.
  private static var runsUnderSanitizer: Bool {
    guard let handle = dlopen(nil, RTLD_NOW) else { return false }
    defer { dlclose(handle) }
    let names: [String] = ["__asan_init", "__tsan_init", "__ubsan_handle_add_overflow"]
    return names.contains(where: { name in dlsym(handle, name) != nil })
  }
}
