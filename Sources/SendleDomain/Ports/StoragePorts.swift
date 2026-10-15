public protocol SettingsStore: Sendable {
  func load() async -> AppSettings
  func save(_ settings: AppSettings) async throws(StorageError)
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
