/// A point of a graph worth marking.
public struct PlotPoint: Hashable, Sendable {
  public enum Kind: Hashable, Sendable {
    case root
    /// Where the curve of an equation in `x` and `y` meets the x axis (for a function this is a root).
    case xIntercept
    case yIntercept
    case minimum
    case maximum
    /// Where two of the curves cross.
    case intersection
  }

  public var kind: Kind
  public var x: Double
  public var y: Double
  /// Which function the point is on (the first of the two, for an intersection).
  public var functionIndex: Int
}

/// Finds the roots, y-intercepts, local extrema and intersections of drawn functions, in `Double`.
///
/// The function is sampled, a sign change or a turn is spotted between samples, and the point is refined by bisection or
/// golden-section search. Poles are told from roots and extrema by checking that the function is steady around the
/// point found. The accuracy is that of `Double` (about 12 digits): enough to place and label a point on a graph.
public enum PlotAnalysis {
  public static func points(
    of functions: [PlotFunction], from xMin: Double, to xMax: Double, samples: Int = 2000
  )
    -> [PlotPoint]
  {
    var points: [PlotPoint] = []
    let sampled = functions.map { function in samplesOf(function.evaluate, from: xMin, to: xMax, count: samples) }

    for (index, function) in functions.enumerated() {
      let f = function.evaluate
      let data = sampled[index]
      let roots = rootsOf(f, data)
      points += roots.map { PlotPoint(kind: .root, x: $0, y: 0, functionIndex: index) }

      for extremum in extremaOf(f, data) {
        // An extremum on the x axis is a root that does not cross it (x² at 0).
        if abs(extremum.y) < 1e-9, !roots.contains(where: { abs($0 - extremum.x) < 1e-6 }) {
          points.append(PlotPoint(kind: .root, x: extremum.x, y: 0, functionIndex: index))
        }
        points.append(
          PlotPoint(kind: extremum.isMaximum ? .maximum : .minimum, x: extremum.x, y: extremum.y, functionIndex: index))
      }

      if xMin <= 0 && 0 <= xMax {
        let y = f(0)
        if y.isFinite && !roots.contains(where: { abs($0) < 1e-9 }) {
          points.append(PlotPoint(kind: .yIntercept, x: 0, y: y, functionIndex: index))
        }
      }
    }

    // Where two functions meet: the roots of their difference.
    if functions.count > 1 {
      for first in 0..<functions.count {
        for second in (first + 1)..<functions.count {
          let f = functions[first].evaluate
          let g = functions[second].evaluate
          let difference: RealFunction = { f($0) - g($0) }
          let data = samplesOf(difference, from: xMin, to: xMax, count: samples)
          for x in rootsOf(difference, data) {
            points.append(PlotPoint(kind: .intersection, x: x, y: f(x), functionIndex: first))
          }
        }
      }
    }
    return points.sorted { $0.x < $1.x }
  }

  /// Where the curve of an equation meets the axes: the roots of the expression with `y` set to 0 (the x-intercepts) and with
  /// `x` set to 0 (the y-intercepts), within `range` of the origin. `index` is the number the points carry, for their colour.
  public static func intercepts(of relation: PlotRelation, index: Int, within range: Double) -> [PlotPoint] {
    let alongX: RealFunction = { relation.evaluate($0, 0) }
    let alongY: RealFunction = { relation.evaluate(0, $0) }
    var points: [PlotPoint] = []
    for x in rootsOf(alongX, samplesOf(alongX, from: -range, to: range, count: 2001)) {
      points.append(PlotPoint(kind: .xIntercept, x: x, y: 0, functionIndex: index))
    }
    for y in rootsOf(alongY, samplesOf(alongY, from: -range, to: range, count: 2001)) {
      points.append(PlotPoint(kind: .yIntercept, x: 0, y: y, functionIndex: index))
    }
    return points
  }

  /// Where the graph of each function meets the curve of each equation: the roots of the expression along the graph.
  public static func crossings(
    of functions: [PlotFunction], with relations: [PlotRelation], from xMin: Double, to xMax: Double,
    samples: Int = 2000
  ) -> [PlotPoint] {
    var points: [PlotPoint] = []
    for (functionIndex, function) in functions.enumerated() {
      for relation in relations where !relation.isRegion {
        let along: RealFunction = { relation.evaluate($0, function.evaluate($0)) }
        for x in rootsOf(along, samplesOf(along, from: xMin, to: xMax, count: samples)) {
          points.append(PlotPoint(kind: .intersection, x: x, y: function.evaluate(x), functionIndex: functionIndex))
        }
      }
    }
    return points
  }

  // MARK: Sampling

  private struct Sample {
    var x: Double
    var y: Double
  }

  private static func samplesOf(_ f: RealFunction, from a: Double, to b: Double, count: Int) -> [Sample] {
    (0..<count).map { index in
      let x = a + (b - a) * Double(index) / Double(count - 1)
      return Sample(x: x, y: f(x))
    }
  }

  // MARK: Roots

  private static func rootsOf(_ f: RealFunction, _ data: [Sample]) -> [Double] {
    var roots: [Double] = []
    func add(_ x: Double) {
      if !roots.contains(where: { abs($0 - x) < 1e-9 * max(1, abs(x)) }) { roots.append(x) }
    }
    for index in 0..<(data.count - 1) {
      let p = data[index]
      let q = data[index + 1]
      guard p.y.isFinite, q.y.isFinite else { continue }
      if p.y == 0 {
        add(p.x)
        continue
      }
      guard p.y * q.y < 0 else { continue }

      var low = p.x
      var high = q.x
      var lowValue = p.y
      for _ in 0..<200 {
        let middle = (low + high) / 2
        let value = f(middle)
        if !value.isFinite { break }
        if value == 0 {
          low = middle
          high = middle
          break
        }
        if (value < 0) == (lowValue < 0) {
          low = middle
          lowValue = value
        } else {
          high = middle
        }
        if high - low <= 1e-15 * max(1, abs(low)) { break }
      }
      let x = (low + high) / 2
      let y = f(x)
      // At a pole the sign changes too, but the value does not shrink toward zero.
      if y.isFinite && abs(y) <= 1e-6 * max(abs(p.y), abs(q.y)) + 1e-9 { add(x) }
    }
    return roots
  }

  // MARK: Extrema

  private struct Extremum {
    var x: Double
    var y: Double
    var isMaximum: Bool
  }

  private static func extremaOf(_ f: RealFunction, _ data: [Sample]) -> [Extremum] {
    var found: [Extremum] = []
    guard data.count >= 3 else { return found }
    // Walk the signs of the slope between samples, leaving out flat steps (two samples equally high on either side of a
    // peak are common, for x² at 0). Where the sign turns, the extremum lies between the sample where the previous slope
    // began and the sample where the new one ends.
    var previousSign = 0.0
    var previousStart = 0
    for index in 0..<(data.count - 1) {
      let a = data[index]
      let b = data[index + 1]
      guard a.y.isFinite, b.y.isFinite else {
        previousSign = 0
        continue
      }
      let slope = b.y - a.y
      guard slope != 0 else { continue }
      let sign = slope > 0 ? 1.0 : -1.0
      defer {
        previousSign = sign
        previousStart = index
      }
      guard previousSign != 0, sign != previousSign else { continue }

      let isMaximum = previousSign > 0
      let low = data[previousStart].x
      let high = b.x
      let x = goldenSection(f, from: low, to: high, maximizing: isMaximum)
      let y = f(x)
      guard y.isFinite, abs(y) < 1e12 else { continue }
      // A pole fools the comparison of samples; a true extremum is steady in a tiny neighbourhood of it.
      let step = (high - low) * 1e-4
      let left = f(x - step)
      let right = f(x + step)
      let tolerance = 1e-3 * max(1, abs(y))
      guard left.isFinite, right.isFinite, abs(left - y) <= tolerance, abs(right - y) <= tolerance else { continue }
      if found.contains(where: { abs($0.x - x) < 1e-7 * max(1, abs(x)) }) { continue }
      found.append(Extremum(x: x, y: y, isMaximum: isMaximum))
    }
    return found
  }

  private static func goldenSection(_ f: RealFunction, from a: Double, to b: Double, maximizing: Bool) -> Double {
    let ratio = (5.0.squareRoot() - 1) / 2
    var low = a
    var high = b
    let sign = maximizing ? -1.0 : 1.0  // minimise sign · f
    var c = high - ratio * (high - low)
    var d = low + ratio * (high - low)
    var fc = sign * f(c)
    var fd = sign * f(d)
    for _ in 0..<200 {
      if high - low <= 1e-14 * max(1, abs(low)) { break }
      if fc < fd {
        high = d
        d = c
        fd = fc
        c = high - ratio * (high - low)
        fc = sign * f(c)
      } else {
        low = c
        c = d
        fc = fd
        d = low + ratio * (high - low)
        fd = sign * f(d)
      }
    }
    return (low + high) / 2
  }
}
