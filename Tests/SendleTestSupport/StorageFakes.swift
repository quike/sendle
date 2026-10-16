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
  private let removalFailure: StorageError?
  private let readFailure: StorageError?

  public init(
    _ passwords: [String: String] = [:],
    removalFailure: StorageError? = nil,
    readFailure: StorageError? = nil
  ) {
    self.passwords = passwords
    self.removalFailure = removalFailure
    self.readFailure = readFailure
  }

  public func password(for account: String) throws(StorageError) -> String? {
    if let readFailure { throw readFailure }
    return passwords[account]
  }

  public func setPassword(_ password: String, for account: String) {
    passwords[account] = password
  }

  public func removePassword(for account: String) throws(StorageError) {
    if let removalFailure { throw removalFailure }
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
