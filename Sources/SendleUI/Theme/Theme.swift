import SendleDomain
import SwiftUI

/// house-control's palette and motion, so Sendle reads as its sibling (spec §3.4).
package enum Theme {
  package static let background = Color(hex: 0x0a0e1a)
  package static let text = Color(hex: 0xf3f5fa)
  package static let muted = Color.white.opacity(0.58)
  package static let faint = Color.white.opacity(0.34)
  package static let glass = Color.white.opacity(0.055)
  package static let glassHigh = Color.white.opacity(0.10)
  package static let line = Color.white.opacity(0.085)
  package static let accent = Color(hex: 0x3d8bff)
  package static let warm = Color(hex: 0xffb46b)
  package static let live = Color(hex: 0x4ade80)
  package static let danger = Color(hex: 0xff5c5c)
  package static let brandStart = Color(hex: 0x7c5cff)
  /// Links and the light blue of active text, such as "Open Amazon's settings ↗".
  package static let link = Color(hex: 0x9cc2ff)
  /// What floats over the books, such as the send bar, and reads over any cover.
  package static let floating = Color(hex: 0x161b29).opacity(0.96)

  package static let action = LinearGradient(
    colors: [accent, Color(hex: 0x2a6fe0)], startPoint: .topLeading, endPoint: .bottomTrailing)
  package static let usbAction = LinearGradient(
    colors: [Color(hex: 0x2fbf6a), Color(hex: 0x1f8f4e)], startPoint: .topLeading,
    endPoint: .bottomTrailing)

  /// Email is always blue and USB always green, wherever a destination shows.
  package static func tint(for kind: DestinationKind) -> Color {
    kind == .usb ? live : accent
  }

  package static func action(for kind: DestinationKind) -> LinearGradient {
    kind == .usb ? usbAction : action
  }

  /// Title cards for books without a cover, from the approved mockups.
  package static let coverGradients: [(Color, Color)] = [
    (Color(hex: 0x1e3a5f), Color(hex: 0x0f2238)), (Color(hex: 0x7a2e3b), Color(hex: 0x3d1520)),
    (Color(hex: 0xc49a3a), Color(hex: 0x6b4f17)), (Color(hex: 0x2f5d50), Color(hex: 0x13302a)),
    (Color(hex: 0x4b3a7a), Color(hex: 0x21183d)), (Color(hex: 0x5a5f66), Color(hex: 0x2a2d31)),
  ]

  package static let cardSize = CGSize(width: 400, height: 620)
  package static let cardRadius: CGFloat = 26
  package static let press = Animation.spring(response: 0.3, dampingFraction: 0.7)
  package static let stagger = 0.028

  /// Items enter 28 ms apart; with Reduce Motion they just appear.
  package static func entrance(index: Int, reduceMotion: Bool) -> AnyTransition {
    guard !reduceMotion else { return .identity }
    return .opacity.combined(with: .offset(y: 8))
      .animation(press.delay(Double(min(index, 12)) * stagger))
  }
}

extension Color {
  /// An sRGB colour from a 0xRRGGBB literal, as the spec's token table writes them.
  package init(hex: UInt32) {
    self.init(
      .sRGB, red: Double(hex >> 16 & 0xff) / 255, green: Double(hex >> 8 & 0xff) / 255,
      blue: Double(hex & 0xff) / 255)
  }
}
