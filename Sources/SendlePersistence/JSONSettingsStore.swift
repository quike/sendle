import Foundation
import SendleDomain

public actor JSONSettingsStore: SettingsStore {
  private let file: JSONFile<AppSettings>
  private let now: @Sendable () -> Date
  private var quarantined: URL?

  public init(directory: URL, now: @escaping @Sendable () -> Date = { Date() }) {
    file = JSONFile(url: directory.appending(path: "settings.json"))
    self.now = now
  }

  public func load() -> AppSettings {
    file.read(quarantiningCorruptAt: now()) { quarantined = $0 } ?? .defaults
  }

  /// Where an unreadable settings file was moved since the last call, so the app can say so once.
  public func takeQuarantinedFile() -> URL? {
    defer { quarantined = nil }
    return quarantined
  }

  @discardableResult
  public func update(
    _ change: @Sendable (inout AppSettings) -> Void
  ) throws(StorageError) -> AppSettings {
    let previous = load()
    var updated = previous
    change(&updated)
    try file.write(updated)
    return previous
  }
}
