import Foundation
import Testing

@testable import MantissaCore

/// `MANTISSA_SEED` and `MANTISSA_SAMPLES` widen the random search, as for the expression tests.
private let seedOffset = UInt64(ProcessInfo.processInfo.environment["MANTISSA_SEED"] ?? "") ?? 0
private let sampleCount = Int(ProcessInfo.processInfo.environment["MANTISSA_SAMPLES"] ?? "") ?? 1500

private func functions(_ text: String, unit: AngleUnit = .radians) -> [PlotFunction] {
  var settings = CalculatorSettings()
  settings.angleUnit = unit
  return Calculator(settings: settings).plotFunctions(text)
}

private func function(_ text: String) throws -> PlotFunction {
  try #require(functions(text).first, "\(text) should be plottable")
}

@Suite("Plot functions")
struct PlotFunctionTests {
  @Test(
    "What counts as something to draw",
    arguments: [
      ("x²−4", 1), ("x", 1), ("y=2x+1", 1), ("y = 3", 1), ("2x+1=y", 1), ("sin(x)", 1), ("1/x", 1),
      ("y=x\ny=−x+4", 2), ("x²\nx+2", 2), ("2+2", 0), ("5", 0), ("x=3", 0), ("x²−4=0", 0), ("a+x", 0), ("y=a", 0),
      ("", 0), ("x+", 0), ("y=x\n5", 0), ("x<3", 0), ("1/0", 0), ("√(−4)x", 1),
    ])
  func plottable(text: String, count: Int) {
    #expect(functions(text).count == count, "\(text.debugDescription)")
  }

  @Test("The compiled function gives the values of the expression")
  func values() throws {
    let parabola = try function("x²−4")
    #expect(parabola.evaluate(3) == 5)
    #expect(parabola.evaluate(0) == -4)
    let sine = try function("sin(x)")
    #expect(abs(sine.evaluate(Double.pi / 6) - 0.5) < 1e-15)
    let root = try function("√x")
    #expect(root.evaluate(9) == 3)
    #expect(root.evaluate(-1).isNaN)
    let cubeRoot = try function("x^(1/3)")
    #expect(abs(cubeRoot.evaluate(-8) + 2) < 1e-12)
    let reciprocal = try function("1/x")
    #expect(reciprocal.evaluate(0).isNaN)  // 1/0 is undefined, not an infinity
    #expect(reciprocal.evaluate(4) == 0.25)
    let logarithm = try function("ln(x)")
    #expect(logarithm.evaluate(-1).isNaN)
    #expect(abs(logarithm.evaluate(M_E) - 1) < 1e-15)
    let absolute = try function("|x−1|")
    #expect(absolute.evaluate(-2) == 3)
    let factorial = try function("x!")
    #expect(factorial.evaluate(5) == 120)
    #expect(factorial.evaluate(2.5).isNaN)
    #expect(try function("2^x").evaluate(10) == 1024)
    #expect(abs(try function("e^x").evaluate(1) - M_E) < 1e-15)
  }

  @Test("Degree mode is built into the function")
  func degrees() throws {
    let sine = try #require(functions("sin(x)", unit: .degrees).first)
    #expect(abs(sine.evaluate(30) - 0.5) < 1e-12)
  }

  @Test("The Double version agrees with the exact evaluation on random expressions in x")
  func agreesWithExactEvaluation() throws {
    var generator = SyntaxGenerator(seed: 515 &+ seedOffset &* 7919)
    generator.includesUnknown = true
    let builder = Builder(angleUnit: .radians)
    var compared = 0
    var failures: [String] = []
    for _ in 0..<sampleCount {
      guard let expression = try? builder.build(generator.make(depth: 3)), expression.freeSymbols == ["x"] else {
        continue
      }
      let compiled = PlotFunction(expression)
      for x in [-3.7, -1.0, -0.5, 0.3, 1.0, 2.5, 7.1] {
        let value = compiled.evaluate(x)
        let exact = try? expression.approximation(precision: 30, values: ["x": BigDecimal("\(x)")!])
        guard let exact else {
          // The exact layer says the value is undefined; the Double version must not invent a finite one.
          if value.isFinite && abs(value) < 1e8 {
            failures.append("\(expression) at \(x): exact undefined, Double \(value)")
          }
          continue
        }
        let reference = exact.doubleValue
        guard abs(reference) < 1e8, value.isFinite || reference.isFinite else { continue }
        compared += 1
        if !(abs(value - reference) <= 1e-7 * max(1, abs(reference))) {
          failures.append("\(expression) at \(x): Double \(value), exact \(reference)")
        }
      }
    }
    #expect(compared > 1000, "only \(compared) comparisons")
    #expect(failures.isEmpty, "\(failures.count) failures; first: \(failures.prefix(5))")
  }
}

@Suite("Plot viewport and sampling")
struct PlotViewportTests {
  @Test("A fitted window takes in the interesting points nearest the origin")
  func fit() throws {
    // x² − 4: roots at ±2 and the vertex at 0 all in view, and the whole of the dip, not the far reaches of the parabola.
    let parabola = PlotViewport.fit([try function("x²−4")])
    #expect(parabola.xMin < -2 && parabola.xMax > 2 && parabola.width < 12)
    #expect(parabola.yMin < -4 && parabola.yMax > 0 && parabola.yMax < 30)

    // A parabola whose only point of interest is the origin still gets a usable window.
    let simple = PlotViewport.fit([try function("x²")])
    #expect(simple.xMin < 0 && simple.xMax > 0 && simple.yMin < 0 && simple.yMax > 8)

    let constant = PlotViewport.fit([try function("y=3")])
    #expect(constant.yMin < 3 && constant.yMax > 3 && constant.height >= 4)

    // sin: the roots and turns nearest 0 are within about ±π, so that is about the window.
    let sine = PlotViewport.fit([try function("sin(x)")])
    #expect(sine.xMin < -3.14 && sine.xMax > 3.14 && sine.width < 14)
    #expect(sine.yMin < -1 && sine.yMax > 1 && sine.height < 6)

    // A line far from the axis near the origin is not stretched down to the axis.
    let far = PlotViewport.fit([try function("y=1000+x")])
    #expect(far.yMin > 900 && far.yMax < 1100)

    // Nothing to mark at all (1/x): the usual window.
    let pole = PlotViewport.fit([try function("1/x")])
    #expect(pole.xMin == -10 && pole.xMax == 10 && pole.height < 1e4 && pole.height >= 4)

    // Two curves: their crossing is in view too.
    let pair = PlotViewport.fit([try function("x²"), try function("x+2")])
    #expect(pair.xMin < -1 && pair.xMax > 2)
  }

  @Test("Panning and zooming keep the point under the finger")
  func panAndZoom() {
    let view = PlotViewport(xMin: -10, xMax: 10, yMin: -5, yMax: 5)
    let panned = view.panned(dx: 3, dy: -1)
    #expect(panned == PlotViewport(xMin: -7, xMax: 13, yMin: -6, yMax: 4))
    let zoomed = view.zoomed(by: 2, aboutX: 4, y: 1)
    #expect(zoomed.width == 10 && zoomed.height == 5)
    // The point (4, 1) stays at the same relative place.
    #expect((4 - zoomed.xMin) / zoomed.width == (4 - view.xMin) / view.width)
    #expect((1 - zoomed.yMin) / zoomed.height == (1 - view.yMin) / view.height)
  }

  @Test("A curve is cut where the function is undefined or has a pole")
  func segments() throws {
    let view = PlotViewport(xMin: -5, xMax: 5, yMin: -5, yMax: 5)
    #expect(PlotSampler.segments(of: try function("x²"), in: view, count: 500).count == 1)
    #expect(PlotSampler.segments(of: try function("x²"), in: view, count: 500)[0].count == 500)
    // 1/x has a pole at 0, so there are two pieces; no sample sits at 0 with an even count.
    #expect(PlotSampler.segments(of: try function("1/x"), in: view, count: 500).count == 2)
    // √x exists only for x ≥ 0.
    let root = PlotSampler.segments(of: try function("√x"), in: view, count: 500)
    #expect(root.count == 1 && root[0].allSatisfy { $0.x >= 0 })
    // tan has poles at ±π/2 and ±3π/2 within [−5, 5]: four poles cut the curve into five pieces.
    #expect(PlotSampler.segments(of: try function("tan(x)"), in: view, count: 1000).count == 5)
    // ln is undefined for x ≤ 0.
    let logarithm = PlotSampler.segments(of: try function("ln(x)"), in: view, count: 500)
    #expect(logarithm.count == 1 && logarithm[0].allSatisfy { $0.x > 0 })
    // Wild values are clamped, not passed through.
    let steep = PlotSampler.segments(of: try function("y=1e300*x"), in: view, count: 100)
    #expect(steep.allSatisfy { $0.allSatisfy { abs($0.y) < 1e4 } })
  }
}

@Suite("Plot analysis")
struct PlotAnalysisTests {
  private func points(_ texts: [String], from a: Double = -10, to b: Double = 10) throws -> [PlotPoint] {
    let functions = try texts.map(function)
    return PlotAnalysis.points(of: functions, from: a, to: b)
  }

  private func near(_ points: [PlotPoint], _ kind: PlotPoint.Kind) -> [Double] {
    points.filter { $0.kind == kind }.map(\.x)
  }

  @Test("Roots, intercept and minimum of a parabola")
  func parabola() throws {
    let found = try points(["x²−4"])
    #expect(near(found, .root).count == 2)
    #expect(abs(near(found, .root)[0] + 2) < 1e-9 && abs(near(found, .root)[1] - 2) < 1e-9)
    let intercept = try #require(found.first { $0.kind == .yIntercept })
    #expect(intercept.x == 0 && intercept.y == -4)
    let minimum = try #require(found.first { $0.kind == .minimum })
    #expect(abs(minimum.x) < 1e-6 && abs(minimum.y + 4) < 1e-9)
    #expect(found.allSatisfy { $0.kind != .maximum })
  }

  @Test("A cubic has a maximum and a minimum, and three roots")
  func cubic() throws {
    let found = try points(["x³−3x"])
    let maximum = try #require(found.first { $0.kind == .maximum })
    let minimum = try #require(found.first { $0.kind == .minimum })
    #expect(abs(maximum.x + 1) < 1e-6 && abs(maximum.y - 2) < 1e-9)
    #expect(abs(minimum.x - 1) < 1e-6 && abs(minimum.y + 2) < 1e-9)
    let roots = near(found, .root)
    #expect(roots.count == 3)
    #expect(abs(roots[0] + 3.squareRoot()) < 1e-9 && abs(roots[1]) < 1e-9 && abs(roots[2] - 3.squareRoot()) < 1e-9)
  }

  @Test("A root that touches the axis without crossing it is found (x² at 0, (x−1)² at 1)")
  func doubleRoot() throws {
    #expect(near(try points(["x²"]), .root).count == 1)
    let shifted = near(try points(["(x−1)^2"]), .root)
    #expect(shifted.count == 1 && abs(shifted[0] - 1) < 1e-6)
  }

  @Test("Sine has a root every π, and maxima and minima between")
  func sine() throws {
    let found = try points(["sin(x)"], from: -7, to: 7)
    let roots = near(found, .root)
    #expect(roots.count == 5)  // −2π, −π, 0, π, 2π
    for (root, expected) in zip(roots, [-2 * Double.pi, -Double.pi, 0, Double.pi, 2 * Double.pi]) {
      #expect(abs(root - expected) < 1e-9)
    }
    #expect(near(found, .maximum).count == 2 && near(found, .minimum).count == 2)
    #expect(abs(near(found, .maximum)[0] + 3 * Double.pi / 2) < 1e-6)
  }

  @Test("Poles are not roots and not extrema")
  func poles() throws {
    #expect(near(try points(["1/x"]), .root).isEmpty)
    #expect(try points(["1/x"]).allSatisfy { $0.kind == .yIntercept || false } || (try points(["1/x"])).isEmpty)
    let tangent = try points(["tan(x)"], from: -4, to: 4)
    // tan has roots at −π, 0, π and no extrema; the poles at ±π/2 are not roots.
    #expect(near(tangent, .root).count == 3)
    #expect(near(tangent, .maximum).isEmpty && near(tangent, .minimum).isEmpty)
    let steady = try points(["1/(x²−1)"])  // two poles; the minimum at 0 is real
    #expect(near(steady, .root).isEmpty)
    #expect(near(steady, .maximum).count == 1 && abs(near(steady, .maximum)[0]) < 1e-6)
  }

  @Test("Where two curves cross")
  func intersections() throws {
    let found = try points(["x²", "x+2"])
    let crossings = found.filter { $0.kind == .intersection }
    #expect(crossings.count == 2)
    #expect(abs(crossings[0].x + 1) < 1e-9 && abs(crossings[0].y - 1) < 1e-9)
    #expect(abs(crossings[1].x - 2) < 1e-9 && abs(crossings[1].y - 4) < 1e-9)
    // A line and a curve that do not meet.
    #expect(try points(["x²", "y=−1"]).filter { $0.kind == .intersection }.isEmpty)
  }

  @Test("Constants, lines and the absolute value")
  func simpleCases() throws {
    let constant = try points(["y=3"])
    #expect(near(constant, .root).isEmpty && constant.filter { $0.kind == .minimum || $0.kind == .maximum }.isEmpty)
    #expect(constant.contains { $0.kind == .yIntercept && $0.y == 3 })
    let line = try points(["2x+1"])
    #expect(near(line, .root).count == 1 && abs(near(line, .root)[0] + 0.5) < 1e-12)
    let absolute = try points(["|x|−2"])
    #expect(near(absolute, .root).count == 2)
    #expect(abs(try #require(absolute.first { $0.kind == .minimum }).y + 2) < 1e-9)
  }

  @Test("The y-intercept only appears when x = 0 is in range")
  func interceptRange() throws {
    #expect(try points(["x²+1"], from: 1, to: 5).allSatisfy { $0.kind != .yIntercept })
    #expect(try points(["x²+1"], from: -1, to: 5).contains { $0.kind == .yIntercept })
  }
}
