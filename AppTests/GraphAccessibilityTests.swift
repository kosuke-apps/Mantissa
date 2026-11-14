import Accessibility
import MantissaCore
import XCTest

@testable import Mantissa

/// What VoiceOver gets for a graph, and the actions that let it move the window.
@MainActor
final class GraphAccessibilityTests: XCTestCase {
  override func setUp() { Localizer.bundle = AppLanguage.english.bundle }
  override func tearDown() { Localizer.bundle = AppLanguage.system.bundle }

  private func graph(_ text: String) -> GraphModel { GraphModel(content: Calculator().plotContent(text)) }

  func testTheSummaryNamesTheCurvesTheWindowAndTheMarkedPoints() {
    let summary = graph("x^2-5x+6=0").spokenSummary
    // An equation is drawn as its two sides, whose crossings are the solutions.
    XCTAssertTrue(summary.hasPrefix("Graph with one curve."), summary)
    XCTAssertTrue(summary.contains("The graph shows x from"), summary)
    let parabola = graph("x^2-5x+6").spokenSummary
    XCTAssertTrue(parabola.contains("(2, 0)"), parabola)
    XCTAssertTrue(parabola.contains("(3, 0)"), parabola)
    XCTAssertTrue(parabola.contains("(0, 6)"), parabola)
    XCTAssertTrue(parabola.contains("Minimum at (2.5, -0.25)"), parabola)
  }

  func testSeveralCurvesAreCounted() {
    XCTAssertTrue(graph("y=x\ny=-x+4").spokenSummary.hasPrefix("Graph with 2 curves."))
  }

  func testTheSummaryIsInJapaneseWhenTheAppIs() {
    Localizer.bundle = AppLanguage.japanese.bundle
    let summary = graph("x^2-5x+6").spokenSummary
    XCTAssertTrue(summary.hasPrefix("曲線が 1 本のグラフ．"), summary)
    XCTAssertTrue(summary.contains("極小は (2.5，-0.25)"), summary)
  }

  func testTheMoveAndZoomActionsChangeTheWindowAsTheGesturesDo() {
    let model = graph("x^2-5x+6")
    let start = model.viewport
    model.pan(byFractionX: 0.25, y: 0)
    XCTAssertEqual(model.viewport.xMin, start.xMin + 0.25 * start.width, accuracy: 1e-9)
    XCTAssertEqual(model.viewport.width, start.width, accuracy: 1e-9)
    model.pan(byFractionX: -0.25, y: 0.25)
    XCTAssertEqual(model.viewport.xMin, start.xMin, accuracy: 1e-9)
    XCTAssertEqual(model.viewport.yMin, start.yMin + 0.25 * start.height, accuracy: 1e-9)
    model.zoom(by: 2)
    XCTAssertEqual(model.viewport.width, start.width / 2, accuracy: 1e-9)
    XCTAssertEqual(
      (model.viewport.xMin + model.viewport.xMax) / 2, start.xMin + start.width / 2, accuracy: 1e-9,
      "zoomed about the middle")
  }

  func testTheAudioGraphHasACurveWithValuesInsideTheWindow() {
    let model = graph("x^2-5x+6")
    let descriptor = GraphChart(graph: model).makeChartDescriptor()
    XCTAssertEqual(descriptor.series.count, 1)
    XCTAssertGreaterThan(descriptor.series[0].dataPoints.count, 40)
    let range = model.viewport.yMin...model.viewport.yMax
    for point in GraphChart.samples(of: model.functions[0], in: model.viewport) {
      XCTAssertTrue(range.contains(point.y))
    }
    // A function with no value somewhere has no point there.
    let root = graph("sqrt(x)")
    let left = PlotViewport(xMin: -4, xMax: 4, yMin: -4, yMax: 4)
    let samples = GraphChart.samples(of: root.functions[0], in: left)
    XCTAssertTrue(samples.allSatisfy { $0.x >= 0 }, "no points where the root is not a real number")
  }
}
