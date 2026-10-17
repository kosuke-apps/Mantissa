import Testing

@testable import MantissaCore

/// Curves and regions that are not the graph of a function: what is drawn for them, and where.
@Suite("Relations in the plane")
struct RelationPlotTests {
  private func content(_ text: String) -> PlotContent { Calculator().plotContent(text) }

  @Test("Which inputs are curves, regions or functions")
  func routing() {
    #expect(content("y=x^2").functions.count == 1 && content("y=x^2").relations.isEmpty)
    #expect(content("x^2+y^2=25").relations.count == 1 && content("x^2+y^2=25").functions.isEmpty)
    #expect(content("x^2/4+y^2/9=1").relations.count == 1)
    #expect(content("x=y^2").relations.count == 1)
    // An inequality is a region whether it has one unknown or two.
    #expect(content("y>x").relations.map(\.kind) == [.greater])
    #expect(content("y<=x^2").relations.map(\.kind) == [.lessOrEqual])
    #expect(content("x^2>=4").relations.map(\.kind) == [.greaterOrEqual])
    #expect(content("x^2+y^2<4").relations.map(\.kind) == [.less])
    // A system is drawn when each line is one or the other.
    let mixed = content("y=x\nx^2+y^2=25")
    #expect(mixed.functions.count == 1 && mixed.relations.count == 1)
    let bands = content("x+y<3\nx-y>1")
    #expect(bands.functions.isEmpty && bands.relations.map(\.kind) == [.less, .greater])
    // Not drawn: no unknown, another letter, a not-equal sign, something unfinished, a chain.
    for text in ["2+3", "x^2+y^2=a", "x≠1", "y>", "1<x<5", "x+y+z=1", "(1"] {
      #expect(content(text).isEmpty, "\(text)")
    }
  }

  @Test("The boundary belongs to the region for ≤ and ≥ only")
  func boundaries() {
    #expect(content("y<=x").relations[0].includesBoundary)
    #expect(content("y>=x").relations[0].includesBoundary)
    #expect(!content("y<x").relations[0].includesBoundary)
    #expect(!content("y>x").relations[0].includesBoundary)
    #expect(content("y>x").relations[0].isRegion)
    #expect(!content("x^2+y^2=1").relations[0].isRegion)
  }

  @Test("The contour of a circle lies on the circle and goes all the way round")
  func circle() throws {
    let relation = try #require(content("x^2+y^2=25").relations.first)
    let window = PlotViewport(xMin: -8, xMax: 8, yMin: -8, yMax: 8)
    let segments = PlotSampler.contour(of: relation, in: window, columns: 80, rows: 80)
    #expect(segments.count > 150)
    for segment in segments {
      for (x, y) in [(segment.x0, segment.y0), (segment.x1, segment.y1)] {
        #expect(abs(x * x + y * y - 25) < 0.05, "(\(x), \(y))")
      }
    }
    let xs = segments.flatMap { [$0.x0, $0.x1] }
    let ys = segments.flatMap { [$0.y0, $0.y1] }
    #expect(abs(xs.min()! + 5) < 0.01 && abs(xs.max()! - 5) < 0.01)
    #expect(abs(ys.min()! + 5) < 0.01 && abs(ys.max()! - 5) < 0.01)
  }

  @Test("The joined contour of a circle is one closed line, and no segment is lost or used twice")
  func lines() throws {
    // x² + y² = 24 passes through no corner of the grid, so every cell edge it crosses is shared by exactly two segments.
    let circle = try #require(content("x^2+y^2=24").relations.first)
    let window = PlotViewport(xMin: -8, xMax: 8, yMin: -8, yMax: 8)
    let closed = PlotSampler.contourLines(of: circle, in: window, columns: 80, rows: 80)
    #expect(closed.count == 1)
    let segments = PlotSampler.contour(of: circle, in: window, columns: 80, rows: 80)
    #expect(closed[0].count == segments.count + 1)
    #expect(closed[0].first == closed[0].last)
    // Consecutive points are the ends of one segment each.
    let ends = Set(segments.map { [$0.x0, $0.y0, $0.x1, $0.y1] })
    for (a, b) in zip(closed[0], closed[0].dropFirst()) {
      #expect(ends.contains([a.x, a.y, b.x, b.y]) || ends.contains([b.x, b.y, a.x, a.y]))
    }

    // Through corners of the grid several segments meet in one point, and the lines may split there; all are still used once.
    let cross = try #require(content("x^2-y^2=0").relations.first)
    let crossing = PlotViewport(xMin: -5, xMax: 5, yMin: -5, yMax: 5)
    let lines = PlotSampler.contourLines(of: cross, in: crossing, columns: 61, rows: 61)
    let total = PlotSampler.contour(of: cross, in: crossing, columns: 61, rows: 61).count
    #expect(lines.map { $0.count - 1 }.reduce(0, +) == total)
  }

  @Test("An ellipse with other half-axes")
  func ellipse() throws {
    let relation = try #require(content("x^2/4+y^2/9=1").relations.first)
    let window = PlotViewport(xMin: -4, xMax: 4, yMin: -4, yMax: 4)
    let segments = PlotSampler.contour(of: relation, in: window, columns: 100, rows: 100)
    for segment in segments {
      let x = segment.x0
      let y = segment.y0
      #expect(abs(x * x / 4 + y * y / 9 - 1) < 0.02, "(\(x), \(y))")
    }
    let ys = segments.flatMap { [$0.y0, $0.y1] }
    #expect(abs(ys.max()! - 3) < 0.01)
  }

  @Test("Two lines crossing: the middle of the cell at the crossing decides the way round")
  func crossing() throws {
    let relation = try #require(content("x^2-y^2=0").relations.first)
    // An even number of cells puts a corner of the grid on the crossing itself; an odd one puts the middle of a cell there.
    for count in [60, 61] {
      let window = PlotViewport(xMin: -5, xMax: 5, yMin: -5, yMax: 5)
      let segments = PlotSampler.contour(of: relation, in: window, columns: count, rows: count)
      for segment in segments {
        #expect(abs(abs(segment.x0) - abs(segment.y0)) < 0.2, "(\(segment.x0), \(segment.y0))")
      }
      for (x, y) in [(3.0, 3.0), (3.0, -3.0), (-3.0, 3.0), (-3.0, -3.0)] {
        #expect(
          segments.contains { abs(($0.x0 + $0.x1) / 2 - x) < 0.5 && abs(($0.y0 + $0.y1) / 2 - y) < 0.5 },
          "no segment near (\(x), \(y)) with \(count) cells")
      }
    }
  }

  @Test("A region covers exactly the cells whose centre satisfies the inequality")
  func region() throws {
    let relation = try #require(content("y>x^2").relations.first)
    let window = PlotViewport(xMin: -3, xMax: 3, yMin: -1, yMax: 9)
    let columns = 60
    let rows = 50
    let runs = PlotSampler.region(of: relation, in: window, columns: columns, rows: rows)
    var covered = Set<Int>()
    for run in runs {
      for column in run.firstColumn..<run.endColumn { covered.insert(run.row * columns + column) }
    }
    var expected = Set<Int>()
    for row in 0..<rows {
      for column in 0..<columns {
        let x = -3 + (Double(column) + 0.5) * 6 / Double(columns)
        let y = -1 + (Double(row) + 0.5) * 10 / Double(rows)
        if y > x * x { expected.insert(row * columns + column) }
      }
    }
    #expect(covered == expected)
    #expect(covered.count > 500)
    // Runs are maximal: no two touch on the same row.
    for (a, b) in zip(runs, runs.dropFirst()) where a.row == b.row { #expect(a.endColumn < b.firstColumn) }
  }

  @Test("An inequality in x alone shades whole columns")
  func band() throws {
    let relation = try #require(content("x^2>=4").relations.first)
    let window = PlotViewport(xMin: -5, xMax: 5, yMin: -5, yMax: 5)
    let runs = PlotSampler.region(of: relation, in: window, columns: 100, rows: 10)
    #expect(runs.count == 20)  // two bands in each of 10 rows
    #expect(
      runs.allSatisfy { $0.firstColumn == 0 && $0.endColumn == 30 || $0.firstColumn == 70 && $0.endColumn == 100 })
  }

  @Test("Cells where the expression is undefined are left out")
  func undefined() throws {
    // x = √y has no value below the x axis; the curve is only where y ≥ 0, and there it is the parabola y = x².
    let relation = try #require(content("x=sqrt(y)").relations.first)
    let window = PlotViewport(xMin: -4, xMax: 4, yMin: -3, yMax: 9)
    let segments = PlotSampler.contour(of: relation, in: window, columns: 80, rows: 120)
    #expect(segments.count > 40)
    for segment in segments {
      #expect(segment.y0 >= -0.1 && segment.y1 >= -0.1)
      // Right at the vertex the curve is vertical and a cell cannot follow it; away from it the fit is close.
      if segment.y0 > 0.5 {
        #expect(abs(segment.x0 - segment.y0.squareRoot()) < 0.05, "(\(segment.x0), \(segment.y0))")
      }
    }
  }

  @Test("The intercepts of a circle are on the axes at its radius")
  func intercepts() throws {
    let relation = try #require(content("x^2+y^2=25").relations.first)
    let points = PlotAnalysis.intercepts(of: relation, index: 2, within: 20)
    let roots = points.filter { $0.kind == .xIntercept }.map(\.x).sorted()
    let heights = points.filter { $0.kind == .yIntercept }.map(\.y).sorted()
    #expect(roots.count == 2 && abs(roots[0] + 5) < 1e-9 && abs(roots[1] - 5) < 1e-9)
    #expect(heights.count == 2 && abs(heights[0] + 5) < 1e-9 && abs(heights[1] - 5) < 1e-9)
    #expect(points.allSatisfy { $0.functionIndex == 2 })
  }
}

@Suite("Windows and crossings for relations")
struct RelationWindowTests {
  private func content(_ text: String) -> PlotContent { Calculator().plotContent(text) }

  @Test("A window matching the shape of the screen keeps the scale equal on both axes")
  func aspect() {
    // 10 × 10 units on a 400 × 300 screen: the y axis has fewer points per unit, so the window grows in x, never shrinks.
    let window = PlotViewport(xMin: -5, xMax: 5, yMin: -5, yMax: 5).matchingAspect(width: 400, height: 300)
    #expect(abs(window.width / 400 - window.height / 300) < 1e-12)
    #expect(window.yMin == -5 && window.yMax == 5)
    #expect(abs(window.xMin + 20.0 / 3) < 1e-12 && abs(window.xMax - 20.0 / 3) < 1e-12)
    let tall = PlotViewport(xMin: -5, xMax: 5, yMin: -5, yMax: 5).matchingAspect(width: 300, height: 400)
    #expect(abs(tall.width / 300 - tall.height / 400) < 1e-12)
    #expect(tall.xMin == -5 && tall.xMax == 5)
    #expect(abs(tall.yMin + 20.0 / 3) < 1e-12 && abs(tall.yMax - 20.0 / 3) < 1e-12)
  }

  @Test("The window of a circle takes in the whole of it, and of an inequality with no intercepts is −10 to 10")
  func fit() {
    let circle = PlotViewport.fit(content("x^2+y^2=25"))
    #expect(circle.xMin < -5 && circle.xMax > 5 && circle.yMin < -5 && circle.yMax > 5)
    #expect(circle.xMax < 15)
    let half = PlotViewport.fit(content("y>x"))
    #expect(half == PlotViewport(xMin: -10, xMax: 10, yMin: -10, yMax: 10))
    // A function alone is fitted as before.
    let function = content("y=x^2-4")
    #expect(PlotViewport.fit(function) == PlotViewport.fit(function.functions))
    // A line and a circle: the window holds both.
    let both = PlotViewport.fit(content("y=x\nx^2+y^2=100"))
    #expect(both.xMin < -10 && both.xMax > 10)
  }

  @Test("A line meets a circle where the roots along the line are")
  func lineAndCircle() {
    let drawn = content("y=x\nx^2+y^2=18")
    let points = PlotAnalysis.crossings(of: drawn.functions, with: drawn.relations, from: -10, to: 10)
    #expect(points.count == 2)
    let xs = points.map(\.x).sorted()
    #expect(abs(xs[0] + 3) < 1e-9 && abs(xs[1] - 3) < 1e-9)
    #expect(points.allSatisfy { abs($0.y - $0.x) < 1e-9 && $0.kind == .intersection })
  }

  @Test("Content draws the same when its expressions and kinds are the same")
  func sameDrawing() {
    #expect(content("x^2+y^2=25").draws(sameAs: content("x^2+y^2=25")))
    #expect(!content("x^2+y^2=25").draws(sameAs: content("x^2+y^2<25")))
    #expect(!content("x^2+y^2=25").draws(sameAs: content("x^2+y^2=16")))
    #expect(content("y=x^2").draws(sameAs: content("y=x^2")))
    #expect(!content("y=x^2").draws(sameAs: content("y=x^2\ny=x")))
  }

  @Test("Regions have no crossings")
  func regionsDoNotCross() {
    let drawn = content("y=x\nx^2+y^2<18")
    #expect(PlotAnalysis.crossings(of: drawn.functions, with: drawn.relations, from: -10, to: 10).isEmpty)
  }
}
