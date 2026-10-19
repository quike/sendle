import Foundation
import SendleDomain
import os

public final class FakeKindleLibrary: KindleLibrary {
  private struct State {
    var result: Result<KindleListing, KindleListingError>
    var resultByVolume: [String: Result<KindleListing, KindleListingError>] = [:]
    var listedVolumes: [KindleVolume] = []
    var gate: Signal?
    var progress: [(done: Int, total: Int)] = []
    var listings = 0
    var inFlight = 0
    var maxConcurrentListings = 0
    var coverRequests: [KindleBookID] = []
  }

  private let state: OSAllocatedUnfairLock<State>
  private let covers: [KindleBookID: Data]

  public init(
    _ result: Result<KindleListing, KindleListingError> = .success(.fixture([])),
    covers: [KindleBookID: Data] = [:]
  ) {
    state = OSAllocatedUnfairLock(initialState: State(result: result))
    self.covers = covers
  }

  /// What the next `listing(of:progress:)` call returns.
  public var result: Result<KindleListing, KindleListingError> {
    get { state.withLock { $0.result } }
    set { state.withLock { $0.result = newValue } }
  }

  /// What listings of `volume` return, ahead of `result`.
  public func setResult(
    _ result: Result<KindleListing, KindleListingError>, for volume: KindleVolume
  ) {
    state.withLock { $0.resultByVolume[volume.id] = result }
  }

  /// The Kindles listed, in order.
  public var listedVolumes: [KindleVolume] { state.withLock { $0.listedVolumes } }

  /// While set, a listing waits for it to fire before answering.
  public var gate: Signal? {
    get { state.withLock { $0.gate } }
    set { state.withLock { $0.gate = newValue } }
  }

  /// What each listing reports before it waits for the gate.
  public var progress: [(done: Int, total: Int)] {
    get { state.withLock { $0.progress } }
    set { state.withLock { $0.progress = newValue } }
  }

  public var listings: Int { state.withLock { $0.listings } }
  /// The most listings that were in flight at the same time.
  public var maxConcurrentListings: Int { state.withLock { $0.maxConcurrentListings } }
  public var coverRequests: [KindleBookID] { state.withLock { $0.coverRequests } }

  public func listing(
    of volume: KindleVolume,
    progress: @escaping @Sendable (_ done: Int, _ total: Int) async -> Void
  ) async throws(KindleListingError) -> KindleListing {
    let (result, gate, steps) = state.withLock { state in
      state.listings += 1
      state.listedVolumes.append(volume)
      state.inFlight += 1
      state.maxConcurrentListings = max(state.maxConcurrentListings, state.inFlight)
      return (state.resultByVolume[volume.id] ?? state.result, state.gate, state.progress)
    }
    defer { state.withLock { $0.inFlight -= 1 } }
    for step in steps {
      await progress(step.done, step.total)
    }
    if let gate, await !gate.waitUnlessCancelled() { throw .cancelled }
    return try result.get()
  }

  public func cover(of book: KindleBook, on volume: KindleVolume, maxPixel: Int) async -> Cover {
    state.withLock { $0.coverRequests.append(book.id) }
    return covers[book.id].map(Cover.image) ?? .none
  }
}

public final class FakeEditionReader: EditionReader {
  private let editions: [BookID: Edition]
  private let log = OSAllocatedUnfairLock<[[BookID]]>(initialState: [])

  public init(_ editions: [BookID: Edition] = [:]) {
    self.editions = editions
  }

  public var requests: [[BookID]] { log.withLock { $0 } }

  public func editions(of books: [Book]) async -> [BookID: Edition] {
    log.withLock { $0.append(books.map(\.id)) }
    return editions.filter { id, _ in books.contains { $0.id == id } }
  }
}

public final class FakeFileDigester: FileDigester {
  private let digests: [URL: String]
  private let log = OSAllocatedUnfairLock<[URL]>(initialState: [])

  public init(_ digests: [URL: String] = [:]) {
    self.digests = digests
  }

  public var requests: [URL] { log.withLock { $0 } }

  public func sha256(of file: URL) async -> String? {
    log.withLock { $0.append(file) }
    return digests[file]
  }
}

public struct FakeASINScheme: ASINScheme {
  public init() {}

  public func asin(forSeed seed: String) -> String {
    "SN:" + seed
  }
}

extension KindleBook {
  public static func fixture(
    path: String = "Moby-Dick - Herman Melville.azw3",
    title: String = "Moby-Dick",
    authors: [String] = ["Herman Melville"],
    source: KindleBookSource = .byHand,
    asin: String? = nil,
    documentType: String? = nil,
    isbn: String? = nil,
    publisher: String? = nil,
    asinFollowsFileName: Bool = false,
    isProtected: Bool = false,
    byteCount: Int64 = 1_000_000,
    modified: Date = Date(timeIntervalSince1970: 1_760_270_400)
  ) -> KindleBook {
    KindleBook(
      id: KindleBookID(relativePath: path),
      title: title,
      authors: authors,
      source: source,
      asin: asin,
      documentType: documentType,
      isbn: isbn,
      publisher: publisher,
      asinFollowsFileName: asinFollowsFileName,
      isProtected: isProtected,
      byteCount: byteCount,
      modified: modified
    )
  }
}

extension KindleListing {
  public static func fixture(_ books: [KindleBook], freeBytes: Int64? = 3_100_000_000)
    -> KindleListing
  {
    KindleListing(books: books, freeBytes: freeBytes)
  }
}
