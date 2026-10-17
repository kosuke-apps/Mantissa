import MantissaCore
import Observation
import SwiftUI

/// What the graph shows: the functions and other curves and regions, the window onto the plane, and the points worth marking.
@MainActor @Observable
final class GraphModel {
  let content: PlotContent
  var viewport: PlotViewport
  private(set) var points: [PlotPoint] = []
  var selected: PlotPoint?
  /// The size of the drawing, once it is known, so that a window with curves of both unknowns can have equal scales.
  private(set) var drawingSize: CGSize?

  var functions: [PlotFunction] { content.functions }

  /// `size` is the size of the drawing the graph replaces, if there was one: the new window is then fitted to it at once.
  init(content: PlotContent, size: CGSize? = nil) {
    self.content = content
    viewport = PlotViewport.fit(content)
    drawingSize = size
    if let size, !content.relations.isEmpty {
      viewport = viewport.matchingAspect(width: Double(size.width), height: Double(size.height))
    }
    findPoints()
  }

  /// Called with the size of the drawing. The first time (and after a reset), a graph with curves in both unknowns gets a
  /// window with the same scale on both axes, so that a circle is round.
  func fit(to size: CGSize) {
    guard size.width > 0, size.height > 0 else { return }
    let isFirst = drawingSize == nil
    drawingSize = size
    guard isFirst, !content.relations.isEmpty else { return }
    viewport = viewport.matchingAspect(width: Double(size.width), height: Double(size.height))
    findPoints()
  }

  /// Finds the points to mark in the window and a little beyond it, so that panning a little shows them at once.
  func findPoints() {
    let margin = viewport.width * 0.5
    let from = viewport.xMin - margin
    let to = viewport.xMax + margin
    var found = PlotAnalysis.points(of: content.functions, from: from, to: to)
    if !content.relations.isEmpty {
      let range = max(abs(from), abs(to), abs(viewport.yMin) + viewport.height, abs(viewport.yMax) + viewport.height)
      for (index, relation) in content.relations.enumerated() where !relation.isRegion {
        found += PlotAnalysis.intercepts(of: relation, index: content.functions.count + index, within: range)
      }
      found += PlotAnalysis.crossings(of: content.functions, with: content.relations, from: from, to: to)
    }
    points = found.sorted { $0.x < $1.x }
    if let selected, !points.contains(selected) { self.selected = nil }
  }

  func reset() {
    viewport = PlotViewport.fit(content)
    if let drawingSize, !content.relations.isEmpty {
      viewport = viewport.matchingAspect(width: Double(drawingSize.width), height: Double(drawingSize.height))
    }
    selected = nil
    findPoints()
  }
}

private let curveColors: [Color] = [.accentColor, .blue, .green, .orange]

/// The graph with its grid, axes, curves and marked points. Dragging pans, pinching zooms, tapping a point shows where it
/// is.
struct GraphCard: View {
  @Bindable var graph: GraphModel

  @State private var panStart: PlotViewport?
  @State private var zoomStart: PlotViewport?

  private let height: CGFloat = 320

  var body: some View {
    GeometryReader { proxy in
      let size = proxy.size
      Canvas { context, size in draw(in: &context, size: size) }
        .onAppear { graph.fit(to: size) }
        .contentShape(Rectangle())
        .gesture(pan(in: size))
        .simultaneousGesture(zoom(in: size))
        .simultaneousGesture(SpatialTapGesture().onEnded { select(near: $0.location, in: size) })
    }
    .frame(height: height)
    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .overlay(alignment: .topTrailing) {
      Button {
        graph.reset()
      } label: {
        Image(systemName: "arrow.counterclockwise")
          .font(.system(size: 15, weight: .medium))
          .frame(width: 34, height: 34)
          .background(.thinMaterial, in: Circle())
      }
      .buttonStyle(.plain)
      .padding(8)
      .accessibilityLabel("Reset the graph")
    }
  }

  // MARK: Coordinates

  private func screen(_ x: Double, _ y: Double, in size: CGSize) -> CGPoint {
    let v = graph.viewport
    return CGPoint(x: (x - v.xMin) / v.width * size.width, y: size.height - (y - v.yMin) / v.height * size.height)
  }

  private func graphPoint(_ point: CGPoint, in size: CGSize, of v: PlotViewport) -> (x: Double, y: Double) {
    (v.xMin + Double(point.x / size.width) * v.width, v.yMin + Double((size.height - point.y) / size.height) * v.height)
  }

  // MARK: Gestures

  private func pan(in size: CGSize) -> some Gesture {
    DragGesture(minimumDistance: 4)
      .onChanged { value in
        guard zoomStart == nil else { return }
        let start = panStart ?? graph.viewport
        panStart = start
        graph.viewport = start.panned(
          dx: -Double(value.translation.width / size.width) * start.width,
          dy: Double(value.translation.height / size.height) * start.height)
      }
      .onEnded { _ in
        panStart = nil
        graph.findPoints()
      }
  }

  private func zoom(in size: CGSize) -> some Gesture {
    MagnifyGesture()
      .onChanged { value in
        let start = zoomStart ?? graph.viewport
        zoomStart = start
        let anchor = graphPoint(value.startLocation, in: size, of: start)
        graph.viewport = start.zoomed(by: Double(value.magnification), aboutX: anchor.x, y: anchor.y)
      }
      .onEnded { _ in
        zoomStart = nil
        graph.findPoints()
      }
  }

  /// A tap picks the marked point within reach of the finger, or clears the choice.
  private func select(near location: CGPoint, in size: CGSize) {
    let reach: CGFloat = 28
    let nearest = graph.points
      .map {
        (
          point: $0,
          distance: hypot(screen($0.x, $0.y, in: size).x - location.x, screen($0.x, $0.y, in: size).y - location.y)
        )
      }
      .filter { $0.distance < reach }
      .min { $0.distance < $1.distance }
    graph.selected = nearest?.point
  }

  // MARK: Drawing

  private func draw(in context: inout GraphicsContext, size: CGSize) {
    drawGrid(in: &context, size: size)
    let first = graph.functions.count
    for (index, relation) in graph.content.relations.enumerated() where relation.isRegion {
      drawRegion(of: relation, color: curveColors[(first + index) % curveColors.count], in: &context, size: size)
    }
    for (index, function) in graph.functions.enumerated() {
      let color = curveColors[index % curveColors.count]
      var path = Path()
      for segment in PlotSampler.segments(of: function, in: graph.viewport, count: max(Int(size.width), 2)) {
        for (offset, sample) in segment.enumerated() {
          let point = screen(sample.x, sample.y, in: size)
          if offset == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
      }
      context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
    }
    for (index, relation) in graph.content.relations.enumerated() {
      drawBoundary(of: relation, color: curveColors[(first + index) % curveColors.count], in: &context, size: size)
    }
    drawPoints(in: &context, size: size)
  }

  /// The cell size, in points, of the grids a relation is sampled on.
  private static let cell: CGFloat = 4

  /// The part of the plane where an inequality holds, as a light tint.
  private func drawRegion(of relation: PlotRelation, color: Color, in context: inout GraphicsContext, size: CGSize) {
    let columns = max(Int((size.width / Self.cell).rounded(.up)), 1)
    let rows = max(Int((size.height / Self.cell).rounded(.up)), 1)
    let width = size.width / CGFloat(columns)
    let height = size.height / CGFloat(rows)
    var path = Path()
    for run in PlotSampler.region(of: relation, in: graph.viewport, columns: columns, rows: rows) {
      // Rows count up from the bottom of the window.
      path.addRect(
        CGRect(
          x: CGFloat(run.firstColumn) * width, y: size.height - CGFloat(run.row + 1) * height,
          width: CGFloat(run.endColumn - run.firstColumn) * width, height: height + 0.5))
    }
    context.fill(path, with: .color(color.opacity(0.2)))
  }

  /// The curve of an equation, or the edge of a region: solid when it belongs to it, dashed when it does not.
  private func drawBoundary(of relation: PlotRelation, color: Color, in context: inout GraphicsContext, size: CGSize) {
    let columns = max(Int((size.width / Self.cell).rounded(.up)), 1)
    let rows = max(Int((size.height / Self.cell).rounded(.up)), 1)
    var path = Path()
    if relation.includesBoundary {
      for segment in PlotSampler.contour(of: relation, in: graph.viewport, columns: columns, rows: rows) {
        path.move(to: screen(segment.x0, segment.y0, in: size))
        path.addLine(to: screen(segment.x1, segment.y1, in: size))
      }
    } else {
      // A dashed line needs the pieces joined, or the pattern starts again with every piece.
      for line in PlotSampler.contourLines(of: relation, in: graph.viewport, columns: columns, rows: rows) {
        for (offset, sample) in line.enumerated() {
          let point = screen(sample.x, sample.y, in: size)
          if offset == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
      }
    }
    let style = StrokeStyle(
      lineWidth: 2.5, lineCap: .round, lineJoin: .round, dash: relation.includesBoundary ? [] : [7, 5])
    context.stroke(path, with: .color(color), style: style)
  }

  /// A step of 1, 2 or 5 times a power of ten that fits about six times into the range.
  private func tickStep(for range: Double) -> Double {
    let rough = range / 6
    let power = pow(10, floor(log10(rough)))
    let fraction = rough / power
    let nice = fraction < 1.5 ? 1.0 : (fraction < 3.5 ? 2.0 : (fraction < 7.5 ? 5.0 : 10.0))
    return nice * power
  }

  private func drawGrid(in context: inout GraphicsContext, size: CGSize) {
    let v = graph.viewport
    let gridColor = Color.secondary.opacity(0.22)
    let axisColor = Color.primary.opacity(0.7)
    let labelColor = Color.secondary

    func label(_ value: Double, step: Double) -> String {
      let text = format(value, step: step)
      return text
    }

    let xStep = tickStep(for: v.width)
    var x = (v.xMin / xStep).rounded(.up) * xStep
    while x <= v.xMax {
      let point = screen(x, 0, in: size)
      var line = Path()
      line.move(to: CGPoint(x: point.x, y: 0))
      line.addLine(to: CGPoint(x: point.x, y: size.height))
      let isAxis = abs(x) < xStep * 1e-9
      context.stroke(line, with: .color(isAxis ? axisColor : gridColor), lineWidth: isAxis ? 1.5 : 1)
      if !isAxis && point.x > 20 && point.x < size.width - 20 {
        let y = min(max(screen(0, 0, in: size).y + 11, 4), size.height - 16)
        context.draw(
          Text(label(x, step: xStep)).font(.system(size: 11)).foregroundColor(labelColor),
          at: CGPoint(x: point.x, y: y), anchor: .top)
      }
      x += xStep
    }

    let yStep = tickStep(for: v.height)
    var y = (v.yMin / yStep).rounded(.up) * yStep
    while y <= v.yMax {
      let point = screen(0, y, in: size)
      var line = Path()
      line.move(to: CGPoint(x: 0, y: point.y))
      line.addLine(to: CGPoint(x: size.width, y: point.y))
      let isAxis = abs(y) < yStep * 1e-9
      context.stroke(line, with: .color(isAxis ? axisColor : gridColor), lineWidth: isAxis ? 1.5 : 1)
      if !isAxis && point.y > 12 && point.y < size.height - 12 {
        let labelX = min(max(screen(0, 0, in: size).x - 11, 24), size.width - 4)
        context.draw(
          Text(label(y, step: yStep)).font(.system(size: 11)).foregroundColor(labelColor),
          at: CGPoint(x: labelX, y: point.y), anchor: .trailing)
      }
      y += yStep
    }
  }

  private func drawPoints(in context: inout GraphicsContext, size: CGSize) {
    for point in graph.points where graph.viewport.xMin <= point.x && point.x <= graph.viewport.xMax {
      let center = screen(point.x, point.y, in: size)
      guard center.y > -10, center.y < size.height + 10 else { continue }
      let isSelected = point == graph.selected
      let color = curveColors[point.functionIndex % curveColors.count]
      let radius: CGFloat = isSelected ? 7 : 4.5
      let circle = Path(
        ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
      context.fill(circle, with: .color(Color(.systemBackground)))
      context.stroke(circle, with: .color(color), lineWidth: isSelected ? 3 : 2)
    }

    guard let selected = graph.selected else { return }
    let anchor = screen(selected.x, selected.y, in: size)
    let text = context.resolve(
      Text("\(Self.name(of: selected.kind)) (\(format(selected.x)), \(format(selected.y)))").font(
        .system(size: 13, weight: .medium)))
    let measured = text.measure(in: size)
    let box = CGSize(width: measured.width + 16, height: measured.height + 10)
    var origin = CGPoint(x: anchor.x - box.width / 2, y: anchor.y - box.height - 14)
    if origin.y < 4 { origin.y = anchor.y + 14 }
    origin.x = min(max(origin.x, 4), size.width - box.width - 4)
    let rect = CGRect(origin: origin, size: box)
    context.fill(Path(roundedRect: rect, cornerRadius: 8), with: .color(Color(.systemBackground)))
    context.stroke(Path(roundedRect: rect, cornerRadius: 8), with: .color(Color.secondary.opacity(0.4)), lineWidth: 1)
    context.draw(text, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
  }

  private static func name(of kind: PlotPoint.Kind) -> String {
    switch kind {
    case .root: return Localizer.string("Root")
    case .xIntercept: return Localizer.string("x-intercept")
    case .yIntercept: return Localizer.string("y-intercept")
    case .minimum: return Localizer.string("Minimum")
    case .maximum: return Localizer.string("Maximum")
    case .intersection: return Localizer.string("Intersection")
    }
  }

  // MARK: Numbers

  /// A number for a label: up to five significant digits, a real minus sign, no trailing zeros.
  private func format(_ value: Double, step: Double? = nil) -> String {
    if abs(value) < 1e-12 * max(1, abs(step ?? 1)) { return "0" }
    var text = String(format: "%.5g", value)
    if text.contains("e") {
      // 1e+06 reads badly; spell the exponent as a power of ten.
      let parts = text.split(separator: "e")
      if parts.count == 2, let exponent = Int(parts[1]) { text = "\(parts[0])×10^\(exponent)" }
    }
    return text.replacingOccurrences(of: "-", with: "−")
  }
}
