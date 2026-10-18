import Foundation

/// What only the app shell can do: open things outside Sendle and close the panel.
@MainActor
public protocol SystemActions: AnyObject {
  func open(_ url: URL)
  /// Shows Sendle.app in Finder, so it can be dragged into the Full Disk Access list.
  func revealApp()
  func closePanel()
  /// Takes the keyboard back from a text field, such as search.
  func endEditing()
  /// Asks for a program, keeping the panel open meanwhile; nil when the user cancels.
  func chooseProgram() async -> URL?
}

public struct StatusItemState: Equatable, Sendable {
  /// An SF Symbol name.
  public let symbolName: String
  /// Shows the red dot.
  public let needsAttention: Bool
  /// "↑ 2/3" while books are being sent.
  public let progress: String?
}
