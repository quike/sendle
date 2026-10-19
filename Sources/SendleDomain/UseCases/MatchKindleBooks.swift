import Foundation

public struct MatchKindleBooks: Sendable {
  private let editions: any EditionReader
  private let digests: any FileDigester
  private let asins: any ASINScheme
  private let history: any SendHistoryStore

  public init(
    editions: any EditionReader,
    digests: any FileDigester,
    asins: any ASINScheme,
    history: any SendHistoryStore
  ) {
    self.editions = editions
    self.digests = digests
    self.asins = asins
    self.history = history
  }

  public func editions(of books: [Book]) async -> [BookID: Edition] {
    await editions.editions(of: books)
  }

  public func callAsFunction(
    _ books: [Book], against listing: [KindleBook], on volume: KindleVolume
  ) async -> KindleMatches {
    let editions = await readEditions(of: books, for: listing)
    return KindleMatcher.matches(
      books: books,
      editions: editions,
      editionASINs: editionASINs(of: books, editions: editions),
      emailed: await emailedBooks(),
      sameContent: await sameContent(of: books, in: listing, on: volume),
      listing: listing)
  }

  /// Only some Kindle books can carry an edition key or an ISBN, and only EPUBs on this Mac can be
  /// read without a download.
  private func readEditions(of books: [Book], for listing: [KindleBook]) async -> [BookID: Edition]
  {
    let couldCarryKey = listing.contains {
      $0.isbn != nil || ($0.source == .sendle && !$0.asinFollowsFileName)
    }
    guard couldCarryKey else { return [:] }
    let readable = books.filter {
      $0.format == .epub && ($0.availability == .ready || $0.availability == .protected)
    }
    guard !readable.isEmpty else { return [:] }
    return await editions.editions(of: readable)
  }

  private func editionASINs(
    of books: [Book], editions: [BookID: Edition]
  ) -> [BookID: Set<String>] {
    var result: [BookID: Set<String>] = [:]
    for book in books {
      guard let edition = editions[book.id], edition.key != nil else { continue }
      result[book.id] = Set(
        (1...FileNaming.editionCopyLimit).map {
          asins.asin(forSeed: FileNaming.asinSeed(for: book, edition: edition, copy: $0))
        })
    }
    return result
  }

  private func emailedBooks() async -> Set<BookID> {
    Set(
      await history.records()
        .filter { $0.destination == .email && $0.outcome == .sent }
        .map(\.bookID))
  }

  private func sameContent(
    of books: [Book], in listing: [KindleBook], on volume: KindleVolume
  ) async -> Set<ContentPair> {
    let kindlePDFs = listing.filter { $0.format == "pdf" }
    guard !kindlePDFs.isEmpty else { return [] }
    var pairs: Set<ContentPair> = []
    var kindleDigests: [KindleBookID: String] = [:]
    var unreadable: Set<KindleBookID> = []
    for book in books where book.format == .pdf && book.availability == .ready {
      let sameSize = kindlePDFs.filter { $0.byteCount == book.sizeBytes }
      guard !sameSize.isEmpty, let digest = await digests.sha256(of: book.fileURL) else {
        continue
      }
      for kindleBook in sameSize where !unreadable.contains(kindleBook.id) {
        if kindleDigests[kindleBook.id] == nil {
          kindleDigests[kindleBook.id] = await digests.sha256(of: kindleBook.url(on: volume))
          if kindleDigests[kindleBook.id] == nil { unreadable.insert(kindleBook.id) }
        }
        if kindleDigests[kindleBook.id] == digest {
          pairs.insert(ContentPair(book: book.id, kindleBook: kindleBook.id))
        }
      }
    }
    return pairs
  }
}
