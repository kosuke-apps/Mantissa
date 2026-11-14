import Accessibility
import MantissaCore
import SwiftUI

/// What VoiceOver is told about a graph: how many curves, the window it shows, and the points worth marking, in words; and the curves
/// themselves as an Audio Graph, which VoiceOver plays as a rising and falling tone and reads out values from.
extension GraphModel {
  private static func number(_ value: Double) -> String {
    let text = String(format: "%.4g", value)
    return text == "-0" ? "0" : text
  }

  private static func point(_ x: Double, _ y: Double) -> String {
    String(format: Localizer.string("(%1$@, %2$@)"), number(x), number(y))
  }

  /// The curves, the window and the marked points as a few sentences.
  var spokenSummary: String {
    let curves = functions.count + content.relations.count
    var sentences: [String] = []
    sentences.append(
      curves == 1
        ? Localizer.string("Graph with one curve.")
        : String(format: Localizer.string("Graph with %@ curves."), String(curves)))
    sentences.append(
      String(
        format: Localizer.string("The graph shows x from %1$@ to %2$@ and y from %3$@ to %4$@."),
        Self.number(viewport.xMin), Self.number(viewport.xMax), Self.number(viewport.yMin), Self.number(viewport.yMax)))
    for marked in points.prefix(8) {
      let key: String
      switch marked.kind {
      case .root: key = "Root at %@."
      case .xIntercept: key = "x-intercept at %@."
      case .yIntercept: key = "y-intercept at %@."
      case .minimum: key = "Minimum at %@."
      case .maximum: key = "Maximum at %@."
      case .intersection: key = "Intersection at %@."
      }
      sentences.append(String(format: Localizer.string(key), Self.point(marked.x, marked.y)))
    }
    return sentences.joined(separator: " ")
  }

  /// Moves the window by a fraction of its size (positive `x` to the right, positive `y` up), as the move actions do.
  func pan(byFractionX x: Double, y: Double) {
    viewport = viewport.panned(dx: x * viewport.width, dy: y * viewport.height)
    findPoints()
  }

  /// Zooms about the middle of the window; a factor above 1 zooms in.
  func zoom(by factor: Double) {
    let centreX = (viewport.xMin + viewport.xMax) / 2
    let centreY = (viewport.yMin + viewport.yMax) / 2
    viewport = viewport.zoomed(by: factor, aboutX: centreX, y: centreY)
    findPoints()
  }
}

/// The curves of a graph as an Audio Graph.
struct GraphChart: AXChartDescriptorRepresentable {
  let graph: GraphModel

  // SwiftUI asks for the descriptor on the main thread.
  func makeChartDescriptor() -> AXChartDescriptor {
    MainActor.assumeIsolated { describe() }
  }

  @MainActor
  private func describe() -> AXChartDescriptor {
    let viewport = graph.viewport
    let xAxis = AXNumericDataAxisDescriptor(
      title: "x", range: viewport.xMin...viewport.xMax, gridlinePositions: []
    ) { String(format: "%.4g", $0) }
    let yAxis = AXNumericDataAxisDescriptor(
      title: "y", range: viewport.yMin...viewport.yMax, gridlinePositions: []
    ) { String(format: "%.4g", $0) }
    let series = graph.functions.enumerated().map { index, function in
      AXDataSeriesDescriptor(
        name: String(format: Localizer.string("Curve %@"), String(index + 1)), isContinuous: true,
        dataPoints: Self.samples(of: function, in: viewport).map { AXDataPoint(x: $0.x, y: $0.y) })
    }
    return AXChartDescriptor(
      title: Localizer.string("Graph"), summary: graph.spokenSummary, xAxis: xAxis, yAxis: yAxis, additionalAxes: [],
      series: series)
  }

  /// The curve sampled across the window. Values outside it are held at its edge, so that the tone stays within its range, and
  /// where the function has no value there is no point.
  static func samples(of function: PlotFunction, in viewport: PlotViewport, count: Int = 80) -> [(x: Double, y: Double)]
  {
    (0...count).compactMap { step in
      let x = viewport.xMin + viewport.width * Double(step) / Double(count)
      let y = function.evaluate(x)
      guard y.isFinite else { return nil }
      return (x, min(max(y, viewport.yMin), viewport.yMax))
    }
  }

  func updateChartDescriptor(_ descriptor: AXChartDescriptor) {
    let fresh = makeChartDescriptor()
    descriptor.summary = fresh.summary
    descriptor.xAxis = fresh.xAxis
    descriptor.yAxis = fresh.yAxis
    descriptor.series = fresh.series
  }
}
