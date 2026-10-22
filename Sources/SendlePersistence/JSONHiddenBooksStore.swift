import Foundation
import SendleDomain

public actor JSONHiddenBooksStore: HiddenBooksStore {
  private struct File: Codable {
    static let currentVersion = 1

    var version = currentVersion
    var books: [String]

    init(_ ids: Set<BookID>) {
      books = ids.map(\.rawValue).sorted()
    }

    var isFromANewerVersion: Bool { version > Self.currentVersion }

    var ids: Set<BookID> { Set(books.map { BookID(rawValue: $0) }) }
  }

  private let file: JSONFile<File>
  private let log: any ActivityLog

  public init(directory: URL, log: any ActivityLog = NoActivityLog()) {
    file = JSONFile(url: directory.appending(path: "hidden.json"), log: log)
    self.log = log
  }

  public func hidden() -> Set<BookID> {
    load().ids
  }

  public func set(_ books: Set<BookID>, hidden: Bool) throws(StorageError) {
    let stored = load()
    // Rewriting a newer file as this version would drop what this version can't read.
    guard !stored.isFromANewerVersion else {
      log.error(.app, "Couldn't save hidden.json: it is from a newer version of Sendle")
      throw .writeFailed("hidden.json is from a newer version of Sendle")
    }
    let updated = hidden ? stored.ids.union(books) : stored.ids.subtracting(books)
    try file.write(File(updated))
  }

  private func load() -> File {
    file.read(quarantiningCorruptAt: Date()) ?? File([])
  }
}
