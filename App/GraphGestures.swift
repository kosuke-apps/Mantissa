import CoreGraphics
import Foundation
import MantissaCore

extension PlotViewport {
  /// The point of the graph at `point` of a drawing of `size`.
  func graphPoint(at point: CGPoint, in size: CGSize) -> (x: Double, y: Double) {
    (xMin + Double(point.x / size.width) * width, yMin + Double((size.height - point.y) / size.height) * height)
  }
}

/// What the graph's drag, pinch and held finger remember from one touch event to the next.
///
/// A gesture that is cut short (a second finger turns a drag into a pinch) may never report that it ended, so nothing here is
/// trusted past the touch it belongs to: each piece remembers where its touch began, and a touch that begins somewhere else starts
/// afresh from the window as it is then. Without that, the drag that a pinch cut short kept the window it had started from, and the
/// next touch moved from that old window: the scale went back to what it was before the pinch.
struct GraphGestureState {
  /// The window a drag moves from, and how far the finger had moved when that window was taken (nothing unless a pinch changed
  /// the window while the drag was going on).
  private struct PanBase {
    var viewport: PlotViewport
    var origin: CGSize
  }

  /// The window a pinch scales from, and when it last changed.
  private struct ZoomBase {
    var startLocation: CGPoint
    var viewport: PlotViewport
    var lastChange: Date
  }

  private var panStartLocation: CGPoint?
  private var panBase: PanBase?
  private var zoomBase: ZoomBase?
  /// A finger is down on the graph following a curve, so the drag is not a pan.
  private(set) var isTracing = false

  /// How long after its last change a pinch counts as going on. A pinch whose end is never reported must not block panning for ever.
  private let pinchGrace: TimeInterval = 0.5

  struct DragResult: Equatable {
    /// The window the drag moves to, or `nil` when it does not move the window (a pinch or a followed curve has the finger).
    var viewport: PlotViewport?
    /// This event began a new drag that moves the window.
    var startsNewDrag: Bool
  }

  /// A drag event: the touch began at `startLocation` and has moved by `translation`; `viewport` is the window now.
  mutating func drag(
    startLocation: CGPoint, translation: CGSize, in size: CGSize, from viewport: PlotViewport, at now: Date = Date()
  ) -> DragResult {
    let isNewDrag = panStartLocation != startLocation
    if isNewDrag {
      // A drag that begins somewhere else is a new touch, whether or not the last one reported its end: it moves from the window
      // as it is now, and is not following a curve (yet).
      panStartLocation = startLocation
      panBase = PanBase(viewport: viewport, origin: .zero)
      isTracing = false
    }
    guard !isPinching(at: now), !isTracing else { return DragResult(viewport: nil, startsNewDrag: false) }
    if !isNewDrag, panBase == nil {
      // The same drag carrying on after a pinch changed the window under it.
      panBase = PanBase(viewport: viewport, origin: translation)
    }
    guard let base = panBase else { return DragResult(viewport: nil, startsNewDrag: false) }
    let moved = base.viewport.panned(
      dx: -Double((translation.width - base.origin.width) / size.width) * base.viewport.width,
      dy: Double((translation.height - base.origin.height) / size.height) * base.viewport.height)
    return DragResult(viewport: moved, startsNewDrag: isNewDrag)
  }

  mutating func dragEnded() {
    panBase = nil
    panStartLocation = nil
  }

  /// A pinch event: the fingers began about `startLocation` and have scaled by `magnification`; returns the window it comes to.
  mutating func pinch(
    startLocation: CGPoint, magnification: Double, in size: CGSize, from viewport: PlotViewport, at now: Date = Date()
  ) -> PlotViewport {
    var base = zoomBase ?? ZoomBase(startLocation: startLocation, viewport: viewport, lastChange: now)
    if base.startLocation != startLocation {
      base = ZoomBase(startLocation: startLocation, viewport: viewport, lastChange: now)
    }
    base.lastChange = now
    zoomBase = base
    // A drag that is still down carries on from the new window.
    panBase = nil
    let anchor = base.viewport.graphPoint(at: startLocation, in: size)
    return base.viewport.zoomed(by: magnification, aboutX: anchor.x, y: anchor.y)
  }

  mutating func pinchEnded() { zoomBase = nil }

  mutating func tracingBegan() { isTracing = true }
  mutating func tracingEnded() { isTracing = false }

  private func isPinching(at now: Date) -> Bool {
    guard let zoomBase else { return false }
    return now.timeIntervalSince(zoomBase.lastChange) < pinchGrace
  }
}
