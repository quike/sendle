import CoreGraphics
import SendleDomain
import SwiftUI

/// The side of the card the floating A–Z card takes.
package enum RailSide: Sendable {
  case leading
  case trailing
}

/// The floating send card and A–Z card: their sizes, where they sit next to the card, and the room
/// the window keeps around the card for them.
package enum FloatingControls {
  /// Between the card and each floating card.
  package static let gap: CGFloat = 10
  package static let sendHeight: CGFloat = 50
  package static let railWidth: CGFloat = 24

  /// Right of the card while the screen has room for the A–Z card there, otherwise left.
  package static func side(
    card: CGRect, screen: CGRect, width: CGFloat = railWidth, gap: CGFloat = gap
  ) -> RailSide {
    card.maxX + gap + width <= screen.maxX ? .trailing : .leading
  }

  /// The arrow's and the shadow's room around the card, plus each floating card with the same
  /// room again for its own shadow.
  package static func margins(_ controls: ControlsStyle, side: RailSide) -> EdgeInsets {
    var margins = PanelView.margins
    guard controls == .floating else { return margins }
    margins.bottom += gap + sendHeight
    switch side {
    case .leading: margins.leading += gap + railWidth
    case .trailing: margins.trailing += gap + railWidth
    }
    return margins
  }

  /// The send card under `card`, in the same coordinates.
  package static func sendFrame(card: CGRect) -> CGRect {
    CGRect(x: card.minX, y: card.maxY + gap, width: card.width, height: sendHeight)
  }

  /// The A–Z card beside `card`, level with `books`: as tall as they are, or `height` centred on
  /// them for the compact bar.
  package static func railFrame(card: CGRect, books: CGRect, side: RailSide, height: CGFloat?)
    -> CGRect
  {
    let height = min(height ?? books.height, books.height)
    let x = side == .trailing ? card.maxX + gap : card.minX - gap - railWidth
    return CGRect(x: x, y: books.midY - height / 2, width: railWidth, height: height)
  }
}

/// Where the panel's window goes under the status item, in screen coordinates. The card sits where
/// it does with attached controls whatever the controls; only the window around it grows.
package struct PanelPlacement: Equatable, Sendable {
  package let card: CGRect
  package let window: CGRect
  package let margins: EdgeInsets
  package let side: RailSide
  /// The status item's centre, from the card's leading edge.
  package let arrowX: CGFloat

  package init(below anchor: CGRect, in screen: CGRect, controls: ControlsStyle) {
    let base = PanelView.margins
    let size = PanelView.windowSize
    let x = max(
      screen.minX + 4 - base.leading,
      min(anchor.midX - size.width / 2, screen.maxX - size.width + base.trailing - 4)
    ).rounded()
    let y = (anchor.minY - size.height + 3).rounded()
    card = CGRect(
      x: x + base.leading, y: y + base.bottom, width: Theme.cardSize.width,
      height: Theme.cardSize.height)
    side = FloatingControls.side(card: card, screen: screen)
    margins = FloatingControls.margins(controls, side: side)
    window = CGRect(
      x: card.minX - margins.leading, y: card.minY - margins.bottom,
      width: card.width + margins.leading + margins.trailing,
      height: card.height + margins.top + margins.bottom)
    arrowX = anchor.midX - card.minX
  }
}
