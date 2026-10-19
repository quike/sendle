import Foundation
import SendleDomain

/// What an earlier listing of a Kindle found, so a later one reads only the books that changed.
package struct KindleListingCache: Sendable {
  private static let version = 1

  private struct Stored: Codable {
    let version: Int
    let books: [KindleBook]
  }

  /// A book's SHA-256, good while the book keeps the size and date it was hashed at.
  package struct Digest: Codable, Hashable, Sendable {
    let byteCount: Int64
    let modified: Date
    let sha256: String

    package init(of book: KindleBook, sha256: String) {
      byteCount = book.byteCount
      modified = book.modified
      self.sha256 = sha256
    }

    package func sha256(of book: KindleBook) -> String? {
      byteCount == book.byteCount && modified == book.modified ? sha256 : nil
    }
  }

  private struct StoredDigests: Codable {
    let version: Int
    let digests: [String: Digest]
  }

  private let directory: URL

  package init(directory: URL) {
    self.directory = directory.appending(path: "kindles", directoryHint: .isDirectory)
  }

  /// The books of the last saved listing by relative path, or none when there is no usable one.
  package func load(device: String) -> [String: KindleBook] {
    guard let data = try? Data(contentsOf: file(for: device)),
      let stored = try? JSONDecoder().decode(Stored.self, from: data),
      stored.version == Self.version
    else { return [:] }
    return Dictionary(stored.books.map { ($0.id.relativePath, $0) }) { first, _ in first }
  }

  /// A cache that can't be written only costs the next listing a full read.
  package func save(_ books: [KindleBook], device: String) {
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let data = try JSONEncoder().encode(Stored(version: Self.version, books: books))
      try data.write(to: file(for: device), options: .atomic)
    } catch {}
  }

  /// The digests of the Kindle's books by relative path.
  package func loadDigests(device: String) -> [String: Digest] {
    guard let data = try? Data(contentsOf: digestFile(for: device)),
      let stored = try? JSONDecoder().decode(StoredDigests.self, from: data),
      stored.version == Self.version
    else { return [:] }
    return stored.digests
  }

  package func saveDigests(_ digests: [String: Digest], device: String) {
    let file = digestFile(for: device)
    do {
      try FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      let data = try JSONEncoder().encode(StoredDigests(version: Self.version, digests: digests))
      try data.write(to: file, options: .atomic)
    } catch {}
  }

  private func file(for device: String) -> URL {
    directory.appending(path: "\(Self.fileName(for: device)).json")
  }

  private func digestFile(for device: String) -> URL {
    directory.appending(path: "digests", directoryHint: .isDirectory)
      .appending(path: "\(Self.fileName(for: device)).json")
  }

  private static func fileName(for device: String) -> String {
    device.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
  }
}
