/// Keeps every USB copy's ASIN its own, so the Kindle never mixes two books' covers or reading
/// positions.
public struct KindleCopyPlanner: Sendable {
  private let asins: any ASINScheme

  public init(asins: any ASINScheme) {
    self.asins = asins
  }

  /// Each copy of a book with an edition key keeps its ASIN number while no other file in `listing`
  /// and no earlier book in `books` has that ASIN. The file the copy overwrites doesn't count, so
  /// it keeps its ASIN. Otherwise the copy moves to the first free number above its own, up to
  /// `FileNaming.editionCopyLimit`, then below it; its name stays. A copy with no free number, a
  /// replacement and a book without a key are left as they are.
  public func plan(
    _ books: [Book], copies: [BookID: KindleCopy], editions: [BookID: Edition],
    listing: [KindleBook]
  ) -> [BookID: KindleCopy] {
    var filesWithASIN: [String: Int] = [:]
    for file in listing {
      if let asin = file.asin { filesWithASIN[asin, default: 0] += 1 }
    }
    let topLevel = Dictionary(
      listing.filter { !$0.id.relativePath.contains("/") }.map {
        ($0.id.relativePath.lowercased(), $0)
      },
      uniquingKeysWith: { first, _ in first })
    var given: Set<String> = []
    var planned = copies
    let limit = FileNaming.editionCopyLimit
    for book in books {
      let copy = copies[book.id] ?? KindleCopy(name: 1, asin: 1)
      guard copy.keptASIN == nil, let edition = editions[book.id], edition.trimmedKey != nil
      else { continue }
      let overwritten =
        topLevel[(FileNaming.copyName(for: book, copy: copy.name) + ".azw3").lowercased()]?.asin
      func asin(_ number: Int) -> String {
        asins.asin(forSeed: FileNaming.asinSeed(for: book, edition: edition, copy: number))
      }
      func isFree(_ number: Int) -> Bool {
        let candidate = asin(number)
        return !given.contains(candidate)
          && filesWithASIN[candidate, default: 0] <= (candidate == overwritten ? 1 : 0)
      }
      let order =
        [copy.asin] + (1...limit).filter { $0 > copy.asin } + (1...limit).filter { $0 < copy.asin }
      let free = order.first(where: isFree) ?? copy.asin
      given.insert(asin(free))
      if free != copy.asin { planned[book.id] = KindleCopy(name: copy.name, asin: free) }
    }
    return planned
  }
}
