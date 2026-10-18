import Foundation
import SendleDomain

/// The library's order under each sort, and the A–Z bar's letter for each book.
package enum LibraryOrder {
  /// Title and author run A to Z, then `#` (digits, other scripts), then books with no author.
  /// Recently added keeps the order the books come in, which is newest first.
  package static func sorted(_ books: [Book], by sort: LibrarySort) -> [Book] {
    sorted(books, by: sort, book: \.self)
  }

  package static func sorted<Element>(
    _ elements: [Element], by sort: LibrarySort, book: (Element) -> Book
  ) -> [Element] {
    guard sort != .recent else { return elements }
    return elements.map { Keyed(element: $0, book: book($0), key: SortKey(book($0), sort)) }
      .sorted(by: Keyed.precedes)
      .map(\.element)
  }

  /// "A" to "Z" or "#"; nil while sorted by when the books were added.
  package static func letter(for book: Book, by sort: LibrarySort) -> String? {
    guard sort != .recent else { return nil }
    return SortKey(book, sort).letter
  }
}

private struct Keyed<Element> {
  let element: Element
  let book: Book
  let key: SortKey

  /// By letter, then key, then title; the book's id settles the rest, so the order never jumps.
  static func precedes(_ lhs: Self, _ rhs: Self) -> Bool {
    if lhs.key.rank != rhs.key.rank { return lhs.key.rank < rhs.key.rank }
    let byKey = lhs.key.text.localizedStandardCompare(rhs.key.text)
    if byKey != .orderedSame { return byKey == .orderedAscending }
    let byTitle = lhs.book.title.localizedStandardCompare(rhs.book.title)
    if byTitle != .orderedSame { return byTitle == .orderedAscending }
    return lhs.book.id.rawValue < rhs.book.id.rawValue
  }
}

private struct SortKey {
  static let noAuthorRank = 27

  /// The key from its first letter or digit, so "¡Ay, Carmela!" files under A.
  let text: String
  let letter: String
  let rank: Int

  init(_ book: Book, _ sort: LibrarySort) {
    let source =
      switch sort {
      case .recent, .title: book.sortTitle ?? book.title
      case .author: book.sortAuthor ?? book.author
      }
    guard let source else {
      text = ""
      letter = "#"
      rank = Self.noAuthorRank
      return
    }
    text = String(source.drop { !$0.isLetter && !$0.isNumber })
    letter = Self.letter(of: text)
    rank = AlphabetIndex.letters.firstIndex(of: letter) ?? AlphabetIndex.letters.count - 1
  }

  /// Accents and case fall away, so "É" and "Ñ" file under E and N.
  private static func letter(of text: String) -> String {
    guard let first = text.first else { return "#" }
    let folded = String(first).folding(
      options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")
    ).uppercased()
    return AlphabetIndex.letters.dropLast().contains(folded) ? folded : "#"
  }
}

/// Where each letter of the A–Z bar leads in the books on screen.
package struct AlphabetIndex: Equatable, Sendable {
  package static let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ#".map(String.init)

  /// The letters that have books, in the bar's order.
  package let lettersWithBooks: [String]
  private let firstBooks: [String: BookID]
  private let letters: [BookID: String]

  /// `books` must already be in `sort` order.
  package init(books: [Book], sort: LibrarySort) {
    var firstBooks: [String: BookID] = [:]
    var letters: [BookID: String] = [:]
    for book in books {
      guard let letter = LibraryOrder.letter(for: book, by: sort) else { continue }
      letters[book.id] = letter
      if firstBooks[letter] == nil { firstBooks[letter] = book.id }
    }
    self.firstBooks = firstBooks
    self.letters = letters
    lettersWithBooks = Self.letters.filter { firstBooks[$0] != nil }
  }

  /// The first book under `letter`; a letter without books leads to the next one that has some,
  /// or past the end, to the last one.
  package func target(for letter: String) -> BookID? {
    guard let position = Self.letters.firstIndex(of: letter) else { return nil }
    let next = Self.letters[position...].first { firstBooks[$0] != nil }
    return (next ?? lettersWithBooks.last).flatMap { firstBooks[$0] }
  }

  package func letter(of id: BookID) -> String? {
    letters[id]
  }

  /// The letter whose header goes above `id`, when it is the first book under it.
  package func header(before id: BookID) -> String? {
    letters[id].flatMap { firstBooks[$0] == id ? $0 : nil }
  }
}
