import SwiftUI

/// How the icon and text buttons answer the pointer, so every one of them does it alike.
package enum ButtonHover {
  package static let animation = Animation.easeOut(duration: 0.15)

  package static func surface(isHovered: Bool, isPressed: Bool) -> Color {
    isHovered || isPressed ? Theme.glassHigh : Theme.glass
  }

  package static func isOver(_ pointer: CGPoint?, _ frame: CGRect) -> Bool {
    pointer.map { frame.contains($0) } ?? false
  }

  /// How much brighter the icon or text gets under the pointer.
  package static func brightness(isHovered: Bool) -> Double {
    isHovered ? 0.12 : 0
  }
}
