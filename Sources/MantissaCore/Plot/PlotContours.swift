/// A short straight piece of a curve, in graph units.
public struct PlotSegment: Equatable, Sendable {
  public var x0: Double
  public var y0: Double
  public var x1: Double
  public var y1: Double
}

/// Cells `firstColumn..<endColumn` of one row of the grid that all satisfy a relation. Rows count up from the bottom.
public struct PlotRun: Equatable, Sendable {
  public var row: Int
  public var firstColumn: Int
  public var endColumn: Int
}

extension PlotSampler {
  /// The curve where the relation's expression is zero, as short segments, by marching squares: the window is cut into
  /// `columns` × `rows` cells, the expression is evaluated at their corners, and where its sign changes between two
  /// corners the curve crosses that edge at the point found by linear interpolation. A cell with an undefined corner
  /// (a square root of a negative number, a division by zero) is left out.
  public static func contour(
    of relation: PlotRelation, in viewport: PlotViewport, columns: Int, rows: Int
  )
    -> [PlotSegment]
  {
    let columns = max(columns, 1)
    let rows = max(rows, 1)
    let dx = viewport.width / Double(columns)
    let dy = viewport.height / Double(rows)
    let stride = columns + 1
    var values = [Double](repeating: .nan, count: stride * (rows + 1))
    for row in 0...rows {
      let y = viewport.yMin + Double(row) * dy
      for column in 0...columns {
        values[row * stride + column] = relation.evaluate(viewport.xMin + Double(column) * dx, y)
      }
    }

    var segments: [PlotSegment] = []
    for row in 0..<rows {
      // Each coordinate is worked out from its own index, so that two cells sharing an edge agree on it to the last bit.
      let y0 = viewport.yMin + Double(row) * dy
      let y1 = viewport.yMin + Double(row + 1) * dy
      for column in 0..<columns {
        let bottomLeft = values[row * stride + column]
        let bottomRight = values[row * stride + column + 1]
        let topLeft = values[(row + 1) * stride + column]
        let topRight = values[(row + 1) * stride + column + 1]
        guard bottomLeft.isFinite, bottomRight.isFinite, topLeft.isFinite, topRight.isFinite else { continue }
        let x0 = viewport.xMin + Double(column) * dx
        let x1 = viewport.xMin + Double(column + 1) * dx

        let mask =
          (bottomLeft >= 0 ? 1 : 0) | (bottomRight >= 0 ? 2 : 0) | (topRight >= 0 ? 4 : 0) | (topLeft >= 0 ? 8 : 0)
        if mask == 0 || mask == 15 { continue }

        // Where the curve crosses each edge of the cell.
        func between(_ a: Double, _ b: Double) -> Double { a / (a - b) }
        let bottom = (x: x0 + dx * between(bottomLeft, bottomRight), y: y0)
        let right = (x: x1, y: y0 + dy * between(bottomRight, topRight))
        let top = (x: x0 + dx * between(topLeft, topRight), y: y1)
        let left = (x: x0, y: y0 + dy * between(bottomLeft, topLeft))
        func add(_ a: (x: Double, y: Double), _ b: (x: Double, y: Double)) {
          segments.append(PlotSegment(x0: a.x, y0: a.y, x1: b.x, y1: b.y))
        }

        switch mask {
        case 1, 14: add(left, bottom)
        case 2, 13: add(bottom, right)
        case 3, 12: add(left, right)
        case 4, 11: add(right, top)
        case 6, 9: add(bottom, top)
        case 7, 8: add(left, top)
        default:
          // Two opposite corners positive: which way the curve goes round them depends on the middle of the cell.
          let centre = (bottomLeft + bottomRight + topLeft + topRight) / 4 >= 0
          let diagonal = mask == 5  // bottom left and top right positive
          if centre == diagonal {
            add(bottom, right)
            add(left, top)
          } else {
            add(left, bottom)
            add(right, top)
          }
        }
      }
    }
    return segments
  }

  /// The same curve as continuous lines: the segments joined end to end where they share an end. A dashed stroke needs it, since
  /// the pattern starts afresh with every separate piece. A closed curve comes back as one line whose last point is its first.
  public static func contourLines(
    of relation: PlotRelation, in viewport: PlotViewport, columns: Int, rows: Int
  )
    -> [[PlotSample]]
  {
    let segments = contour(of: relation, in: viewport, columns: columns, rows: rows)
    // The two cells either side of an edge work out the crossing of it from the same two values, so the shared end is the
    // same number in both and can be found by exact comparison.
    struct End: Hashable {
      var x: Double
      var y: Double
    }
    var touching: [End: [Int]] = [:]
    for (index, segment) in segments.enumerated() {
      touching[End(x: segment.x0, y: segment.y0), default: []].append(index)
      touching[End(x: segment.x1, y: segment.y1), default: []].append(index)
    }
    var used = [Bool](repeating: false, count: segments.count)

    /// The segment other than `index` that has an end at `end`, if it is not yet used.
    func next(from end: End, after index: Int) -> Int? {
      touching[end]?.first { $0 != index && !used[$0] }
    }

    var lines: [[PlotSample]] = []
    for start in segments.indices where !used[start] {
      used[start] = true
      let first = segments[start]
      var line = [PlotSample(x: first.x0, y: first.y0), PlotSample(x: first.x1, y: first.y1)]
      // Forward from the end of the first segment.
      var index = start
      while let following = next(from: End(x: line[line.count - 1].x, y: line[line.count - 1].y), after: index) {
        used[following] = true
        let segment = segments[following]
        let tail = line[line.count - 1]
        line.append(
          segment.x0 == tail.x && segment.y0 == tail.y
            ? PlotSample(x: segment.x1, y: segment.y1) : PlotSample(x: segment.x0, y: segment.y0))
        index = following
      }
      // Backward from the start.
      index = start
      var front: [PlotSample] = []
      var head = line[0]
      while let preceding = next(from: End(x: head.x, y: head.y), after: index) {
        used[preceding] = true
        let segment = segments[preceding]
        head =
          segment.x0 == head.x && segment.y0 == head.y
          ? PlotSample(x: segment.x1, y: segment.y1) : PlotSample(x: segment.x0, y: segment.y0)
        front.append(head)
        index = preceding
      }
      lines.append(front.reversed() + line)
    }
    return lines
  }

  /// The cells of a `columns` × `rows` grid over the window whose centre satisfies the relation, as runs along each row.
  public static func region(of relation: PlotRelation, in viewport: PlotViewport, columns: Int, rows: Int) -> [PlotRun]
  {
    let columns = max(columns, 1)
    let rows = max(rows, 1)
    let dx = viewport.width / Double(columns)
    let dy = viewport.height / Double(rows)
    var runs: [PlotRun] = []
    for row in 0..<rows {
      let y = viewport.yMin + (Double(row) + 0.5) * dy
      var start: Int?
      for column in 0..<columns {
        let value = relation.evaluate(viewport.xMin + (Double(column) + 0.5) * dx, y)
        if value.isFinite && relation.holds(value) {
          if start == nil { start = column }
        } else if let first = start {
          runs.append(PlotRun(row: row, firstColumn: first, endColumn: column))
          start = nil
        }
      }
      if let first = start { runs.append(PlotRun(row: row, firstColumn: first, endColumn: columns)) }
    }
    return runs
  }
}
