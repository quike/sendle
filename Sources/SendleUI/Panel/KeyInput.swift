import SendleDomain

/// A key press in the panel, as the app shell reads it from AppKit.
public struct KeyInput: Equatable, Sendable {
  public enum Key: Equatable, Sendable {
    case escape
    case up
    case down
    case left
    case right
    case character(String)
  }

  public let key: Key
  /// ⌘ and no other modifier.
  public let command: Bool
  /// A text field has the keyboard, so typing keys belong to it.
  public let isEditingText: Bool

  public init(_ key: Key, command: Bool = false, isEditingText: Bool = false) {
    self.key = key
    self.command = command
    self.isEditingText = isEditingText
  }
}

package enum PanelCommand: Equatable, Sendable {
  case escape
  case move(MoveDirection)
  case selectAll
  case layout(LibraryLayout)
  case focusSearch
  case openSettings
}

extension KeyInput {
  /// The spec's shortcuts (§3.4). Keys a text field needs while typing aren't taken from it.
  package var panelCommand: PanelCommand? {
    switch key {
    case .escape:
      return .escape
    // Up and down leave a text field, as in Spotlight; PanelModel only takes them on the library.
    case .up: return command ? nil : .move(.up)
    case .down: return command ? nil : .move(.down)
    case .left: return arrow(.left)
    case .right: return arrow(.right)
    case .character(let character):
      guard command else { return nil }
      switch character.lowercased() {
      case "a": return isEditingText ? nil : .selectAll
      case "1": return .layout(.grid)
      case "2": return .layout(.list)
      case "3": return .layout(.shelf)
      case "f": return .focusSearch
      case ",": return .openSettings
      default: return nil
      }
    }
  }

  private func arrow(_ direction: MoveDirection) -> PanelCommand? {
    command || isEditingText ? nil : .move(direction)
  }
}
