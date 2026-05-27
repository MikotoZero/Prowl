import AppKit
import ComposableArchitecture

/// Side effects targeting the app's Dock tile: the pending-notification badge
/// and the attention bounce. Wrapping these in a dependency keeps the reducer
/// testable and matches how the other AppKit side effects are injected.
struct DockClient {
  /// Show (`true`) or clear (`false`) the notification badge on the Dock tile.
  var setNotificationBadge: @MainActor @Sendable (_ isVisible: Bool) -> Void
  /// Bounce the Dock icon according to the configured mode. `.off` is a no-op.
  var bounce: @MainActor @Sendable (_ mode: DockBounceMode) -> Void
}

extension DockClient: DependencyKey {
  static let liveValue = DockClient(
    setNotificationBadge: { isVisible in
      // An empty (but non-nil) label renders the bare red badge dot; `nil`
      // hides it. A glyph inside the pill would just look redundant.
      NSApplication.shared.dockTile.badgeLabel = isVisible ? "" : nil
    },
    bounce: { mode in
      switch mode {
      case .off:
        break
      case .once:
        _ = NSApp.requestUserAttention(.informationalRequest)
      case .continuous:
        _ = NSApp.requestUserAttention(.criticalRequest)
      }
    }
  )

  static let testValue = DockClient(
    setNotificationBadge: { _ in },
    bounce: { _ in }
  )
}

extension DependencyValues {
  var dockClient: DockClient {
    get { self[DockClient.self] }
    set { self[DockClient.self] = newValue }
  }
}
