import AppKit
import SendleDomain

/// A key press in the panel, as the app shell reads it from AppKit.
public struct KeyInput: Equatable, Sendable {
  public enum Key: Equatable, Sendable {
    case escape
    case up
    case down
    case left
    case right
    case returnKey
    case character(String)
  }

  public let key: Key
  /// ⌘ and no other modifier.
  public let command: Bool
  /// A text field has the keyboard, so typing keys belong to it.
  public let isEditingText: Bool
  /// The key is held down and this is one of its repeats.
  public let isRepeat: Bool

  public init(
    _ key: Key, command: Bool = false, isEditingText: Bool = false, isRepeat: Bool = false
  ) {
    self.key = key
    self.command = command
    self.isEditingText = isEditingText
    self.isRepeat = isRepeat
  }

  /// A key as AppKit reports it. Only ⌘⇧⌥⌃ count as modifiers, so Caps Lock changes nothing.
  public init?(
    keyCode: UInt16,
    characters: String?,
    modifierFlags: NSEvent.ModifierFlags,
    isEditingText: Bool,
    isRepeat: Bool = false
  ) {
    let key: Key
    switch keyCode {
    case 53: key = .escape
    case 123: key = .left
    case 124: key = .right
    case 125: key = .down
    case 126: key = .up
    case 36, 76: key = .returnKey
    default:
      guard let characters, !characters.isEmpty else { return nil }
      key = .character(characters)
    }
    self.init(
      key, command: modifierFlags.intersection(.typing) == .command, isEditingText: isEditingText,
      isRepeat: isRepeat)
  }
}

/// The editing shortcuts a menu bar app has no Edit menu for.
public enum TextEditingCommand: Equatable, Sendable {
  case cut
  case copy
  case paste
  case selectAll
  case undo
  case redo

  public init?(characters: String?, modifierFlags: NSEvent.ModifierFlags) {
    let flags = modifierFlags.intersection(.typing)
    guard flags.contains(.command), flags.isSubset(of: [.command, .shift]) else { return nil }
    switch (characters?.lowercased(), flags.contains(.shift)) {
    case ("x", false): self = .cut
    case ("c", false): self = .copy
    case ("v", false): self = .paste
    case ("a", false): self = .selectAll
    case ("z", false): self = .undo
    case ("z", true): self = .redo
    default: return nil
    }
  }
}

extension NSEvent.ModifierFlags {
  fileprivate static let typing: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
}

package enum PanelCommand: Equatable, Sendable {
  case escape
  /// Return: the screen's main action.
  case confirm
  case move(MoveDirection)
  case selectAll
  case layout(LibraryLayout)
  case focusSearch
  case refresh
  case openSettings
  case editDetails
  /// ⌘L: looks the book in the details sheet up online.
  case lookUp
  case undo
}

extension KeyInput {
  /// The spec's shortcuts (§3.4). Keys a text field needs while typing aren't taken from it.
  package var panelCommand: PanelCommand? {
    switch key {
    case .escape:
      return .escape
    case .returnKey:
      return command ? nil : .confirm
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
      case "r": return .refresh
      case ",": return .openSettings
      case "i": return isEditingText ? nil : .editDetails
      case "l": return .lookUp
      case "z": return isEditingText ? nil : .undo
      default: return nil
      }
    }
  }

  private func arrow(_ direction: MoveDirection) -> PanelCommand? {
    command || isEditingText ? nil : .move(direction)
  }
}
