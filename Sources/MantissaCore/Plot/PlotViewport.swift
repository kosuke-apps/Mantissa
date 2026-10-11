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

  /// A view that shows the interesting part of `functions`: x from −10 to 10, and y from where most of the curves lie,
  /// with some room, always taking in the x axis when it is not far away.
  public static func fit(_ functions: [PlotFunction]) -> PlotViewport {
    let xMin = -10.0
    let xMax = 10.0
    var values: [Double] = []
    for function in functions {
      for index in 0...600 {
        let y = function.evaluate(xMin + (xMax - xMin) * Double(index) / 600)
        if y.isFinite && abs(y) < 1e9 { values.append(y) }
      }
    }
    guard values.count >= 2 else { return PlotViewport(xMin: xMin, xMax: xMax, yMin: -10, yMax: 10) }
    values.sort()
    var low = values[Int(Double(values.count - 1) * 0.05)]
    var high = values[Int(Double(values.count - 1) * 0.95)]
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
