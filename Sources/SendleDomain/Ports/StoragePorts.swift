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
