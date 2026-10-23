import SwiftUI

/// How a screen or a page comes and goes in the panel, all on the press spring.
package enum ScreenMotion: Equatable, Sendable {
  /// Comes up over the card from its bottom edge and goes back down.
  case cover
  /// Slides in from this edge and leaves towards it.
  case slide(Edge)
  /// Reduce Motion: a quick crossfade.
  case fade

  /// Settings, the logs and the duplicates' review.
  package static func sheet(reduceMotion: Bool) -> ScreenMotion {
    reduceMotion ? .fade : .cover
  }

  /// The front page stays on the leading side and a section's page on the trailing one, so
  /// opening a section pushes it in and going back pops it.
  package static func settingsPage(_ section: SettingsSection?, reduceMotion: Bool)
    -> ScreenMotion
  {
    reduceMotion ? .fade : .slide(section == nil ? .leading : .trailing)
  }

  /// The books come in from their side of the Library | On Kindle switch.
  package static func books(_ side: LibrarySide, reduceMotion: Bool) -> ScreenMotion {
    reduceMotion ? .fade : .slide(side == .library ? .leading : .trailing)
  }

  /// The press spring, or a quick fade with Reduce Motion.
  package static func animation(reduceMotion: Bool) -> Animation {
    reduceMotion ? .easeOut(duration: 0.15) : Theme.press
  }

  package var transition: AnyTransition {
    switch self {
    case .cover: .move(edge: .bottom)
    case .slide(let edge): .move(edge: edge).combined(with: .opacity)
    case .fade: .opacity
    }
  }
}
