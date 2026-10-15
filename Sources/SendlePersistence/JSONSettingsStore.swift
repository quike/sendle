import Foundation
import SendleDomain

public actor JSONSettingsStore: SettingsStore {
  private let file: JSONFile<AppSettings>
  private let now: @Sendable () -> Date

  public init(directory: URL, now: @escaping @Sendable () -> Date = { Date() }) {
    file = JSONFile(url: directory.appending(path: "settings.json"))
    self.now = now
  }

  public func load() -> AppSettings {
    file.read(quarantiningCorruptAt: now()) ?? .defaults
  }

  public func save(_ settings: AppSettings) throws(StorageError) {
    try file.write(settings)
  }
}
