import SwiftUI
import UIKit

/// How much room the calculator has, which decides how it is laid out.
///
/// The width the calculator is given is measured, not the kind of device: the same app runs on an iPhone, on an iPad full screen, in
/// Split View, in Slide Over, in a Stage Manager window and in a resizable window on a Mac, and the size classes say "compact" for
/// different widths in each. Under 640 pt the layout is the iPhone's, whatever the device.
enum WindowClass: Equatable {
  /// The iPhone layout: one page of keys at a time under a scrolling workspace.
  case compact
  /// An iPad in portrait, or a window of about half a large iPad: the workspace above, a keyboard with two pages in view.
  case regular
  /// An iPad in landscape, or a wide window: the answer and the graph side by side.
  case wide
}

struct WindowMetrics: Equatable {
  var size: CGSize

  var width: CGFloat { size.width }
  var height: CGFloat { size.height }

  var kind: WindowClass { width < 640 ? .compact : (width < 900 ? .regular : .wide) }

  /// How much larger than on the iPhone the formula and the answer are drawn.
  var contentScale: CGFloat { kind == .compact ? 1 : 1.25 }

  /// A column of earlier problems fits beside the calculator.
  var showsHistoryColumn: Bool { width >= 1180 && height >= 600 }

  /// The height of a row of keys: 54 pt as on the iPhone, and on a larger window 8.5 % of its height, so that a short window gets
  /// smaller keys and a workspace that can still be read.
  var keyRowHeight: CGFloat { kind == .compact ? 54 : min(max(height * 0.085, 46), 68) }

  /// The size of the screen, for the first frame, before the window has been measured.
  static var firstGuess: WindowMetrics { WindowMetrics(size: UIScreen.main.bounds.size) }
}

private struct WindowMetricsKey: EnvironmentKey {
  static let defaultValue = WindowMetrics(size: CGSize(width: 402, height: 874))
}

extension EnvironmentValues {
  /// The room the calculator has; the root view measures it.
  var window: WindowMetrics {
    get { self[WindowMetricsKey.self] }
    set { self[WindowMetricsKey.self] = newValue }
  }
}
