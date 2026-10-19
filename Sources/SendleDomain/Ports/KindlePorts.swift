import Foundation

public protocol KindleLibrary: Sendable {
  /// Lists what is on the Kindle without changing it, reporting how many books are done.
  func listing(
    of volume: KindleVolume,
    progress: @escaping @Sendable (_ done: Int, _ total: Int) async -> Void
  ) async throws(KindleListingError) -> KindleListing

  func cover(of book: KindleBook, on volume: KindleVolume, maxPixel: Int) async -> Cover
}

public protocol EditionReader: Sendable {
  func editions(of books: [Book]) async -> [BookID: Edition]
}

public protocol FileDigester: Sendable {
  /// The file's SHA-256 in lowercase hex, or nil when it can't be read.
  func sha256(of file: URL) async -> String?
}

/// The 10-character ASIN Sendle gives a book it writes, derived from a seed.
public protocol ASINScheme: Sendable {
  func asin(forSeed seed: String) -> String
}
