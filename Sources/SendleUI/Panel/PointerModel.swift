import CoreGraphics
import Observation
import SwiftUI

/// Where the pointer is over the panel, so a button style can tell it is under the pointer
/// without holding hover state at each button.
@Observable @MainActor
package final class PointerModel {
  /// The coordinates `location` is in: the whole panel window.
  nonisolated package static var space: NamedCoordinateSpace { .named("panel") }

  package var location: CGPoint?

  package init() {}
}
