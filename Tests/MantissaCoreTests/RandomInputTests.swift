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
      case 7: return pick(["dot", "cross"]) + "(" + expression(depth - 1) + "," + expression(depth - 1) + ")"
      default: return pick(["+", "-"]) + expression(depth - 1)
      }
    }

    mutating func statement() -> String {
      switch generator.next() % 6 {
      case 0, 1: return expression(3) + pick(RandomInputTests.relations) + expression(3)
      case 2: return expression(3) + "=" + expression(2) + "\n" + expression(3) + "=" + expression(2)
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
  /// app, and under a sanitizer slower again. `MANTISSA_TIME_LIMIT=n` sets it.
  private static var limit: Double {
    if let text = ProcessInfo.processInfo.environment["MANTISSA_TIME_LIMIT"], let seconds = Double(text) {
      return seconds
    }
    return runsUnderSanitizer ? 80 : 20
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
