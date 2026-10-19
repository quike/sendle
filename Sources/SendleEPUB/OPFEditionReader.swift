import Darwin
import Foundation
import SendleDomain

/// Reads each library EPUB's edition from its package, once, and remembers it until the book
/// changes. It never reads a book that isn't on this Mac, so it can't trigger an iCloud download.
public actor OPFEditionReader: EditionReader {
  private struct Entry: Codable {
    var modified: Int
    var edition: Edition
  }

  private struct Cache: Codable {
    var version = 1
    var entries: [String: Entry] = [:]
  }

  private let cacheFile: URL
  private var cache: Cache?

  public init(cacheFile: URL) {
    self.cacheFile = cacheFile
  }

  public func editions(of books: [Book]) async -> [BookID: Edition] {
    var cache = loadedCache()
    var found: [BookID: Edition] = [:]
    var changed = false
    for book in books where book.format == .epub && Self.isOnThisMac(book) {
      if Task.isCancelled { break }
      let path = book.fileURL.path(percentEncoded: false)
      guard let modified = Self.localModificationTime(ofFileAt: path) else { continue }
      if let entry = cache.entries[path], entry.modified == modified {
        found[book.id] = entry.edition
        continue
      }
      guard let edition = Self.edition(of: book) else { continue }
      cache.entries[path] = Entry(modified: modified, edition: edition)
      found[book.id] = edition
      changed = true
    }
    self.cache = cache
    if changed { save(cache) }
    return found
  }

  /// Nil when the book's package can't be read, so that is never remembered as an edition
  /// without a key.
  private static func edition(of book: Book) -> Edition? {
    var isDirectory: ObjCBool = false
    guard
      FileManager.default.fileExists(
        atPath: book.fileURL.path(percentEncoded: false), isDirectory: &isDirectory)
    else { return nil }
    if isDirectory.boolValue {
      return withoutDownloads { OPFReader.package(inEPUBAt: book.fileURL)?.edition }
    }
    let folder = FileManager.default.temporaryDirectory
      .appending(path: "SendleEditions-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: folder) }
    guard (try? DittoExtractor().extract(book.fileURL, into: folder)) != nil else { return nil }
    return OPFReader.package(inEPUBAt: folder)?.edition
  }

  private static func isOnThisMac(_ book: Book) -> Bool {
    book.availability == .ready || book.availability == .protected
  }

  /// Seconds since 1970. Nil when the file is missing or is an iCloud placeholder.
  private static func localModificationTime(ofFileAt path: String) -> Int? {
    var info = stat()
    guard lstat(path, &info) == 0, info.st_flags & UInt32(SF_DATALESS) == 0 else { return nil }
    return Int(info.st_mtimespec.tv_sec)
  }

  /// An unreadable file counts as empty.
  private func loadedCache() -> Cache {
    if let cache { return cache }
    guard let data = try? Data(contentsOf: cacheFile),
      let stored = try? JSONDecoder().decode(Cache.self, from: data), stored.version == 1
    else { return Cache() }
    return stored
  }

  private func save(_ cache: Cache) {
    guard let data = try? JSONEncoder().encode(cache) else { return }
    try? FileManager.default.createDirectory(
      at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: cacheFile, options: .atomic)
  }
}
