import CryptoKit
import Foundation
import SendleDomain

public actor InMemoryMetadataEditStore: MetadataEditStore {
  private var stored: MetadataEdits
  public private(set) var covers: [BookID: Data] = [:]
  public nonisolated let coverFolder: URL
  private let failure: MetadataEditError?

  public init(
    _ edits: MetadataEdits = MetadataEdits(),
    coverFolder: URL = URL(filePath: "/edit-covers", directoryHint: .isDirectory),
    failure: MetadataEditError? = nil
  ) {
    stored = edits
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
      updated.books[book, default: BookEdit()].cover = Self.coverName(for: book, data: data)
      covers[book] = data
    case .revert:
      updated.books[book]?.cover = nil
      covers[book] = nil
    }
    stored = updated
  }

  private static func coverName(for book: BookID, data: Data) -> String {
    let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
    let id = book.rawValue.addingPercentEncoding(withAllowedCharacters: safe) ?? "book"
    let digest = SHA256.hash(data: data).prefix(6).map { String(format: "%02x", $0) }.joined()
    return "\(id)-\(digest).jpg"
  }
}
