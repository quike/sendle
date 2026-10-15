import Foundation
import SendleDomain

public actor JSONSendHistoryStore: SendHistoryStore {
  public static let defaultLimit = 1_000

  private let file: JSONFile<[SendRecord]>
  private let limit: Int
  private let now: @Sendable () -> Date

  public init(
    directory: URL,
    limit: Int = defaultLimit,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    file = JSONFile(url: directory.appending(path: "history.json"))
    self.limit = limit
    self.now = now
  }

  public func records() -> [SendRecord] {
    file.read(quarantiningCorruptAt: now()) ?? []
  }

  /// Keeps only the newest `limit` records.
  public func append(_ record: SendRecord) throws(StorageError) {
    let all = records() + [record]
    try file.write(Array(all.suffix(limit)))
  }
}
