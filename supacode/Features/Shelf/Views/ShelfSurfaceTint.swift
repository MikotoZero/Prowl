import SwiftUI

/// Shared color logic for the Shelf's tinted *surfaces* — the spine
/// background fill and the toolbar tint band above the open book — so the
/// open book's spine and the band read as one continuous "L" framing the
/// terminal's top and left edges.
///
/// A repo with a user-pinned color tints its surfaces with that color. An
/// uncolored repo falls back to a neutral surface that reads as near-black
/// in dark mode and near-white in light (`Color.primary` composited over
/// the window background at low alpha), so the shelf stays calm until the
/// user opts into a color.
///
/// This intentionally covers only surface *fills*. The header icon and the
/// active-tab highlight keep using the app accent as their uncolored
/// fallback (see `ShelfSpineView.effectiveTintColor`), so an uncolored repo
/// still gets an accent icon / tab marker on its otherwise-neutral spine.
enum ShelfSurfaceTint {
  /// Base hue for a surface fill: the pinned color, or `Color.primary` for
  /// the neutral fallback.
  static func base(for color: RepositoryColorChoice?) -> Color {
    color?.color ?? .primary
  }

  /// Peak fill alpha for the open book's surface (the band, and the open
  /// spine at proximity 0). Independent of window transparency, so the
  /// spine and the toolbar band stay in lockstep at the same alpha
  /// regardless of `background-opacity`. The neutral fallback uses a
  /// gentler peak because `Color.primary` reads as a distinct panel at far
  /// lower opacity than a saturated hue (0.20 of primary would look like a
  /// glaring mid-gray rather than the subtle near-black / near-white
  /// surface we want).
  static func peakAlpha(for color: RepositoryColorChoice?) -> Double {
    color == nil ? 0.10 : 0.20
  }
}
