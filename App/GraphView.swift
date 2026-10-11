import MantissaCore
import Observation
import SwiftUI

/// What the graph shows: the functions, the window onto the plane, and the points worth marking.
@MainActor @Observable
final class GraphModel {
  let functions: [PlotFunction]
  var viewport: PlotViewport
  private(set) var points: [PlotPoint] = []
  var selected: PlotPoint?

  init(functions: [PlotFunction]) {
    self.functions = functions
    viewport = PlotViewport.fit(functions)
    findPoints()
  }

  /// Finds the points to mark in the window and a little beyond it, so that panning a little shows them at once.
  func findPoints() {
    let margin = viewport.width * 0.5
    points = PlotAnalysis.points(of: functions, from: viewport.xMin - margin, to: viewport.xMax + margin)
    if let selected, !points.contains(selected) { self.selected = nil }
  }

  func reset() {
    viewport = PlotViewport.fit(functions)
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
    drawPoints(in: &context, size: size)
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
    case .root: return String(localized: "Root")
    case .yIntercept: return String(localized: "y-intercept")
    case .minimum: return String(localized: "Minimum")
    case .maximum: return String(localized: "Maximum")
    case .intersection: return String(localized: "Intersection")
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
