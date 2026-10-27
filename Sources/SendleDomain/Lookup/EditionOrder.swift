public enum EditionOrder {
  private static let limit = 10

  /// The first ten editions worth showing: one per ISBN, the book's language first, then those
  /// with an ISBN, then the newest.
  public static func ranked(_ editions: [FoundEdition], language: String?) -> [FoundEdition] {
    let wanted = language.flatMap(LanguageTag.primary)
    var seen: Set<String> = []
    let distinct = editions.filter { edition in
      guard let isbn = edition.isbn else { return true }
      return seen.insert(isbn).inserted
    }
    let keyed = distinct.enumerated().map {
      (key: key(of: $0.element, at: $0.offset, wanted: wanted), edition: $0.element)
    }
    return keyed.sorted { $0.key < $1.key }.prefix(limit).map(\.edition)
  }

  /// Smaller sorts first; the position keeps equal editions in their original order.
  private static func key(
    of edition: FoundEdition, at position: Int, wanted: String?
  ) -> (Int, Int, Int, Int) {
    let inLanguage = wanted != nil && edition.language.flatMap(LanguageTag.primary) == wanted
    let year = edition.year.flatMap { Int($0) }
    return (inLanguage ? 0 : 1, edition.isbn == nil ? 1 : 0, year.map { -$0 } ?? 1, position)
  }
}
