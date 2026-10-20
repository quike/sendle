/// Keeps every USB copy's ASIN its own, so the Kindle never mixes two books' covers or reading
/// positions.
public struct KindleCopyPlanner: Sendable {
  private let asins: any ASINScheme

  public init(asins: any ASINScheme) {
    self.asins = asins
  }

  /// Each copy of a book with an edition key moves to the first ASIN number, up to
  /// `FileNaming.editionCopyLimit`, whose ASIN no file in `listing` and no earlier book in
  /// `books` has; its name stays. Replacements and books without a key are left as they are.
  public func plan(
    _ books: [Book], copies: [BookID: KindleCopy], editions: [BookID: Edition],
    listing: [KindleBook]
  ) -> [BookID: KindleCopy] {
    var taken = Set(listing.compactMap(\.asin))
    var planned = copies
    for book in books {
      let copy = copies[book.id] ?? KindleCopy(name: 1, asin: 1)
      guard copy.keptASIN == nil, let edition = editions[book.id], edition.trimmedKey != nil
      else { continue }
      func asin(_ number: Int) -> String {
        asins.asin(forSeed: FileNaming.asinSeed(for: book, edition: edition, copy: number))
      }
      let free =
        stride(from: copy.asin, through: FileNaming.editionCopyLimit, by: 1)
        .first { !taken.contains(asin($0)) } ?? copy.asin
      taken.insert(asin(free))
      if free != copy.asin { planned[book.id] = KindleCopy(name: copy.name, asin: free) }
    }
    return planned
  }
}
