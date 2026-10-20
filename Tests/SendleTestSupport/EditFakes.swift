import Foundation
import SendleDomain

public actor InMemoryMetadataEditStore: MetadataEditStore {
  public private(set) var stored: MetadataEdits
  public private(set) var covers: [BookID: Data] = [:]
  public nonisolated let coverFolder: URL
  private let failure: MetadataEditError?

  public init(
    _ edits: MetadataEdits = MetadataEdits(),
    coverFolder: URL = URL(filePath: "/edit-covers", directoryHint: .isDirectory),
    failure: MetadataEditError? = nil
  ) {
    self.stored = edits
    self.coverFolder = coverFolder
    self.failure = failure
  }

  public func edits() -> MetadataEdits {
    stored
  }

  public func update(
    book: BookID, cover: CoverChange, _ change: @Sendable (inout MetadataEdits) -> Void
  ) throws(MetadataEditError) {
    if let failure { throw failure }
    var updated = stored
    change(&updated)
    switch cover {
    case .keep:
      break
    case .replace(let data):
      updated.books[book, default: BookEdit()].cover = "\(book.rawValue).jpg"
      covers[book] = data
    case .revert:
      updated.books[book]?.cover = nil
      covers[book] = nil
    }
    stored = updated
  }
}
