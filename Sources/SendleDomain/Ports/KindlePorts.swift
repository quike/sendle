import Foundation

public protocol KindleLibrary: Sendable {
  /// Lists what is on the Kindle without changing it, reporting how many books are done.
  func listing(
    of volume: KindleVolume,
    progress: @escaping @Sendable (_ done: Int, _ total: Int) async -> Void
  ) async throws(KindleListingError) -> KindleListing

  func cover(of book: KindleBook, on volume: KindleVolume, maxPixel: Int) async -> Cover
}

public enum KindleRemovalError: Error, Hashable, Sendable {
  case changedSinceListed
  case deviceDisconnected
  /// A file now sits at this path, relative to the Kindle's root, where a held part would go back.
  case occupied(String)
  case failed(String)

  /// Lower case, for "…: <detail>" lines.
  public var detail: String {
    switch self {
    case .changedSinceListed: "it changed on the Kindle since Sendle read it"
    case .deviceDisconnected: "the Kindle was unplugged"
    case .occupied(let path): "another file is at \(path) now"
    case .failed(let detail): detail
    }
  }
}

public enum HeldPart: String, Hashable, Sendable {
  case book, sidecar, cover
}

/// A book moved aside on a Kindle, where the Kindle can't list it, until it is put back or removed.
public struct HeldBook: Identifiable, Hashable, Sendable {
  public let id: UUID
  public let book: KindleBook
  public let volume: KindleVolume
  /// What was moved aside, in order: always .book, then .sidecar and .cover when they were moved.
  public let parts: [HeldPart]

  public init(id: UUID = UUID(), book: KindleBook, volume: KindleVolume, parts: [HeldPart]) {
    self.id = id
    self.book = book
    self.volume = volume
    self.parts = parts
  }
}

public protocol KindleBookRemover: Sendable {
  /// Moves `book`'s own files aside on `volume`, where the Kindle can't list them. `listing` is
  /// the listing `book` came from.
  func hold(_ book: KindleBook, listedWith listing: [KindleBook], on volume: KindleVolume)
    async throws(KindleRemovalError) -> HeldBook

  func restore(_ held: HeldBook) async throws(KindleRemovalError)

  func finalize(_ held: HeldBook) async throws(KindleRemovalError)

  /// Removes whatever earlier runs left held on `volume`; returns how many held books it removed.
  func clearLeftovers(on volume: KindleVolume) async -> Int
}

extension KindleBookRemover {
  /// Hold, then finalize at once: Replace's removal.
  public func removeForGood(
    _ book: KindleBook, listedWith listing: [KindleBook], on volume: KindleVolume
  ) async throws(KindleRemovalError) {
    let held = try await hold(book, listedWith: listing, on: volume)
    try await finalize(held)
  }
}

public protocol EditionReader: Sendable {
  func editions(of books: [Book]) async -> [BookID: Edition]
}

public protocol FileDigester: Sendable {
  /// The file's SHA-256 in lowercase hex, or nil when it can't be read.
  func sha256(of file: URL) async -> String?
}

public protocol KindleDigester: Sendable {
  /// The SHA-256 of a book on the Kindle in lowercase hex, or nil when it can't be read.
  func sha256(of book: KindleBook, on volume: KindleVolume) async -> String?
}

/// The 10-character ASIN Sendle gives a book it writes, derived from a seed.
public protocol ASINScheme: Sendable {
  func asin(forSeed seed: String) -> String
}
