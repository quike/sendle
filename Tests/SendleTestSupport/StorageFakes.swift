import SendleDomain

public actor InMemorySettingsStore: SettingsStore {
  public private(set) var settings: AppSettings
  private let failure: StorageError?

  public init(_ settings: AppSettings = .defaults, failure: StorageError? = nil) {
    self.settings = settings
    self.failure = failure
  }

  public func load() -> AppSettings {
    settings
  }

  @discardableResult
  public func update(
    _ change: @Sendable (inout AppSettings) -> Void
  ) throws(StorageError) -> AppSettings {
    if let failure { throw failure }
    let previous = settings
    change(&settings)
    return previous
  }
}

public actor MemorySecretStore: SecretStore {
  public private(set) var passwords: [String: String]

  public init(_ passwords: [String: String] = [:]) {
    self.passwords = passwords
  }

  public func password(for account: String) -> String? {
    passwords[account]
  }

  public func setPassword(_ password: String, for account: String) {
    passwords[account] = password
  }

  public func removePassword(for account: String) {
    passwords[account] = nil
  }
}

public actor InMemorySendHistoryStore: SendHistoryStore {
  private var stored: [SendRecord] = []
  private let failure: StorageError?

  public init(failure: StorageError? = nil) {
    self.failure = failure
  }

  public func records() -> [SendRecord] {
    stored
  }

  public func append(_ record: SendRecord) throws(StorageError) {
    if let failure { throw failure }
    stored.append(record)
  }
}
