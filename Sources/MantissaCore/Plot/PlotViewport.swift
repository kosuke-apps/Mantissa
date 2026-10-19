/// The part of the plane a graph shows.
public struct PlotViewport: Equatable, Sendable {
  public var xMin: Double
  public var xMax: Double
  public var yMin: Double
  public var yMax: Double

  public init(xMin: Double, xMax: Double, yMin: Double, yMax: Double) {
    self.xMin = xMin
    self.xMax = xMax
    self.yMin = yMin
    self.yMax = yMax
  }

  public var width: Double { xMax - xMin }
  public var height: Double { yMax - yMin }

  /// Moves the view by the given amounts in graph units.
  public func panned(dx: Double, dy: Double) -> PlotViewport {
    PlotViewport(xMin: xMin + dx, xMax: xMax + dx, yMin: yMin + dy, yMax: yMax + dy)
  }

  /// Scales the view about the point (`x`, `y`), which stays where it is on screen. A factor above 1 zooms in.
  public func zoomed(by factor: Double, aboutX x: Double, y: Double) -> PlotViewport {
    let scale = 1 / factor
    return PlotViewport(
      xMin: x + (xMin - x) * scale, xMax: x + (xMax - x) * scale, yMin: y + (yMin - y) * scale,
      yMax: y + (yMax - y) * scale)
  }

  /// The same window, widened about its centre in whichever direction has more screen to spare, so that a length on the x axis
  /// is as long on screen as the same length on the y axis in a drawing of `width` × `height`. Nothing is cut off, and
  /// circles look round.
  public func matchingAspect(width: Double, height: Double) -> PlotViewport {
    guard width > 0, height > 0 else { return self }
    let perPoint = max(self.width / width, self.height / height)
    let centreX = (xMin + xMax) / 2
    let centreY = (yMin + yMax) / 2
    return PlotViewport(
      xMin: centreX - perPoint * width / 2, xMax: centreX + perPoint * width / 2, yMin: centreY - perPoint * height / 2,
      yMax: centreY + perPoint * height / 2)
  }

  /// A window on everything an input draws: `fit` for the functions, and for the other curves and regions a square window
  /// that takes in where they meet the axes (or −10 to 10 when they do not), with room around. Both, when there are both.
  public static func fit(_ content: PlotContent) -> PlotViewport {
    guard !content.relations.isEmpty else { return fit(content.functions) }
    var extent = 0.0
    for (index, relation) in content.relations.enumerated() {
      // Only the points nearest the origin count: where a curve crosses an axis again and again (sin x > 1/2), the window
      // shows a few of the crossings and not all those out to 100.
      let points = PlotAnalysis.intercepts(of: relation, index: index, within: 100)
      for kind in [PlotPoint.Kind.xIntercept, .yIntercept] {
        let nearest = points.filter { $0.kind == kind }.map { max(abs($0.x), abs($0.y)) }.sorted().prefix(4)
        extent = max(extent, nearest.max() ?? 0)
      }
    }
    let half = extent > 1e-6 ? extent * 1.6 : 10
    let relations = PlotViewport(xMin: -half, xMax: half, yMin: -half, yMax: half)
    guard !content.functions.isEmpty else { return relations }
    let functions = fit(content.functions)
    return PlotViewport(
      xMin: min(functions.xMin, relations.xMin), xMax: max(functions.xMax, relations.xMax),
      yMin: min(functions.yMin, relations.yMin), yMax: max(functions.yMax, relations.yMax))
  }

  /// A window on the interesting part of `functions`: wide enough for the points nearest the origin that are worth marking
  /// (roots, turning points, crossings) with some room around them, and as high as the curves are there, with the x axis in
  /// view unless the curves are far from it. Curves with nothing to mark get x from −10 to 10.
  public static func fit(_ functions: [PlotFunction]) -> PlotViewport {
    // Look for the points of interest well beyond the usual window and keep the ones nearest the origin.
    let nearest = PlotAnalysis.points(of: functions, from: -30, to: 30, samples: 1200)
      .map(\.x).sorted { abs($0) < abs($1) }.prefix(5)
    var xMin = -10.0
    var xMax = 10.0
    if !nearest.isEmpty {
      let xs = Array(nearest) + [0]
      let low = xs.min()!
      let high = xs.max()!
      let pad = (high - low) * 0.3
      xMin = low - pad
      xMax = high + pad
      if xMax - xMin < 6 {
        let middle = (xMin + xMax) / 2
        xMin = middle - 3
        xMax = middle + 3
      }
    }

    var values: [Double] = []
    for function in functions {
      for index in 0...600 {
        let y = function.evaluate(xMin + (xMax - xMin) * Double(index) / 600)
        if y.isFinite && abs(y) < 1e9 { values.append(y) }
      }
    }
    guard values.count >= 2 else { return PlotViewport(xMin: xMin, xMax: xMax, yMin: -10, yMax: 10) }
    values.sort()
    var low = values[Int(Double(values.count - 1) * 0.03)]
    var high = values[Int(Double(values.count - 1) * 0.97)]
    if high - low < 1e-9 {
      // A constant: show it in the middle with a symmetric window.
      let level = (low + high) / 2
      let half = max(1, abs(level))
      low = level - half
      high = level + half
    }
    let span = high - low
    // Take in the x axis unless the curve sits far from it.
    if low > 0 && low < 2 * span { low = -span * 0.1 }
    if high < 0 && -high < 2 * span { high = span * 0.1 }
    let pad = (high - low) * 0.15
    var yMin = low - pad
    var yMax = high + pad
    if yMax - yMin < 4 {
      let middle = (yMax + yMin) / 2
      yMin = middle - 2
      yMax = middle + 2
    }
    return PlotViewport(xMin: xMin, xMax: xMax, yMin: yMin, yMax: yMax)
  }
}

/// A point of a curve in graph units.
public struct PlotSample: Equatable, Sendable {
  public var x: Double
  public var y: Double
}

public enum PlotSampler {
  /// The pieces of a curve to draw across `viewport`, sampled `count` times. A piece ends where the function is undefined and
  /// where it jumps across the window (a pole such as the one of 1/x at 0), so that no line is drawn through a gap.
  public static func segments(of function: PlotFunction, in viewport: PlotViewport, count: Int) -> [[PlotSample]] {
    let count = max(count, 2)
    let height = viewport.height
    // Values far outside the window are clamped so that the coordinates stay sane.
    let lower = viewport.yMin - 20 * height
    let upper = viewport.yMax + 20 * height
    var segments: [[PlotSample]] = []
    var current: [PlotSample] = []
    var previous: Double?

    for index in 0..<count {
      let x = viewport.xMin + viewport.width * Double(index) / Double(count - 1)
      let y = function.evaluate(x)
      guard y.isFinite else {
        if !current.isEmpty { segments.append(current) }
        current = []
        previous = nil
        continue
      }
      if let previous, abs(y - previous) > 3 * height {
        if !current.isEmpty { segments.append(current) }
        current = []
      }
      current.append(PlotSample(x: x, y: min(max(y, lower), upper)))
      previous = y
    }
    if !current.isEmpty { segments.append(current) }
    return segments.filter { $0.count > 1 }
  }
}
