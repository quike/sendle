import Foundation

public protocol SettingsStore: Sendable {
  func load() async -> AppSettings
  /// Applies `change` to the stored settings in one step, so writers never undo each other, and
  /// returns the settings as they were before the change.
  @discardableResult
  func update(
    _ change: @Sendable (inout AppSettings) -> Void
  ) async throws(StorageError) -> AppSettings
}

public protocol SecretStore: Sendable {
  func password(for account: String) async throws(StorageError) -> String?
  func setPassword(_ password: String, for account: String) async throws(StorageError)
  func removePassword(for account: String) async throws(StorageError)
}

public protocol SendHistoryStore: Sendable {
  func records() async -> [SendRecord]
  func append(_ record: SendRecord) async throws(StorageError)
}

public enum CoverChange: Hashable, Sendable {
  case keep
  case replace(Data)
  case revert
}

public enum MetadataEditError: Error, Hashable, Sendable {
  case unreadableImage
  case imageTooLarge
  case storage(StorageError)
}

public protocol MetadataEditStore: Sendable {
  /// Where the cover images that `BookEdit.cover` names are kept.
  var coverFolder: URL { get }
  func edits() async -> MetadataEdits
  /// Applies `change` and `cover` (for `book`) in one step; nothing changes when it throws.
  func update(
    book: BookID, cover: CoverChange, _ change: @Sendable (inout MetadataEdits) -> Void
  ) async throws(MetadataEditError)
}
