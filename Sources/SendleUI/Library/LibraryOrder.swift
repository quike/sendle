import Foundation
import SendleDomain

/// What sorting reads from a book, whether it is in the library or on a Kindle.
package struct SortFields {
  /// What a title sort files by: a book's sort title when it has one.
  package let title: String
  package let author: String?
  /// Settles books filed under the same key.
  package let tiebreak: String
  package let id: String

  package init(title: String, author: String?, tiebreak: String, id: String) {
    self.title = title
    self.author = author
    self.tiebreak = tiebreak
    self.id = id
  }

  fileprivate init(_ book: Book) {
    self.init(
      title: book.sortTitle ?? book.title, author: book.sortAuthor ?? book.author,
      tiebreak: book.title, id: book.id.rawValue)
  }
}

/// The library's order under each sort, and the A–Z bar's letter for each book.
package enum LibraryOrder {
  /// The A–Z bar's letters, A to Z then `#`.
  package static let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ#".map(String.init)

  /// Title and author run A to Z, then `#` (digits, other scripts), then books with no author.
  /// Recently added keeps the order the books come in, which is newest first.
  package static func sorted(_ books: [Book], by sort: LibrarySort) -> [Book] {
    sorted(books, by: sort, book: \.self)
  }

  package static func sorted<Element>(
    _ elements: [Element], by sort: LibrarySort, book: (Element) -> Book
  ) -> [Element] {
    sorted(elements, by: sort) { SortFields(book($0)) }
  }

  package static func sorted<Element>(
    _ elements: [Element], by sort: LibrarySort, fields: (Element) -> SortFields
  ) -> [Element] {
    guard sort != .recent else { return elements }
    return elements.map { element in
      let fields = fields(element)
      return Keyed(element: element, fields: fields, key: SortKey(fields, sort))
    }
    .sorted(by: Keyed.precedes)
    .map(\.element)
  }

  /// "A" to "Z" or "#"; nil while sorted by when the books were added.
  package static func letter(for book: Book, by sort: LibrarySort) -> String? {
    letter(for: SortFields(book), by: sort)
  }

  package static func letter(for fields: SortFields, by sort: LibrarySort) -> String? {
    guard sort != .recent else { return nil }
    return SortKey(fields, sort).letter
  }
}

private struct Keyed<Element> {
  let element: Element
  let fields: SortFields
  let key: SortKey

  /// By letter, then key, then title; the book's id settles the rest, so the order never jumps.
  static func precedes(_ lhs: Self, _ rhs: Self) -> Bool {
    if lhs.key.rank != rhs.key.rank { return lhs.key.rank < rhs.key.rank }
    let byKey = lhs.key.text.localizedStandardCompare(rhs.key.text)
    if byKey != .orderedSame { return byKey == .orderedAscending }
    let byTitle = lhs.fields.tiebreak.localizedStandardCompare(rhs.fields.tiebreak)
    if byTitle != .orderedSame { return byTitle == .orderedAscending }
    return lhs.fields.id < rhs.fields.id
  }
}

private struct SortKey {
  static let noAuthorRank = 27

  /// The key from its first letter or digit, so "¡Ay, Carmela!" files under A.
  let text: String
  let letter: String
  let rank: Int

  init(_ fields: SortFields, _ sort: LibrarySort) {
    let source =
      switch sort {
      case .recent, .title: fields.title
      case .author: fields.author
      }
    guard let source else {
      text = ""
      letter = "#"
      rank = Self.noAuthorRank
      return
    }
    text = String(source.drop { !$0.isLetter && !$0.isNumber })
    letter = Self.letter(of: text)
    rank = LibraryOrder.letters.firstIndex(of: letter) ?? LibraryOrder.letters.count - 1
  }

  /// Accents and case fall away, so "É" and "Ñ" file under E and N.
  private static func letter(of text: String) -> String {
    guard let first = text.first else { return "#" }
    let folded = String(first).folding(
      options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")
    ).uppercased()
    return LibraryOrder.letters.dropLast().contains(folded) ? folded : "#"
  }
}

/// Where each letter of the A–Z bar leads among the books on screen, the library's or a Kindle's.
package struct AlphabetIndex<ID: Hashable & Sendable>: Equatable, Sendable {
  /// The letters that have books, in the bar's order.
  package let lettersWithBooks: [String]
  private let firstBooks: [String: ID]
  private let letters: [ID: String]

  /// `elements` must already be in `sort` order.
  package init<Element>(
    _ elements: [Element], sort: LibrarySort, id: (Element) -> ID,
    fields: (Element) -> SortFields
  ) {
    var firstBooks: [String: ID] = [:]
    var letters: [ID: String] = [:]
    for element in elements {
      guard let letter = LibraryOrder.letter(for: fields(element), by: sort) else { continue }
      let id = id(element)
      letters[id] = letter
      if firstBooks[letter] == nil { firstBooks[letter] = id }
    }
    self.firstBooks = firstBooks
    self.letters = letters
    lettersWithBooks = LibraryOrder.letters.filter { firstBooks[$0] != nil }
  }

  /// The first book under `letter`; a letter without books leads to the next one that has some,
  /// or past the end, to the last one.
  package func target(for letter: String) -> ID? {
    guard let position = LibraryOrder.letters.firstIndex(of: letter) else { return nil }
    let next = LibraryOrder.letters[position...].first { firstBooks[$0] != nil }
    return (next ?? lettersWithBooks.last).flatMap { firstBooks[$0] }
  }

  package func letter(of id: ID) -> String? {
    letters[id]
  }

  /// The letter whose header goes above `id`, when it is the first book under it.
  package func header(before id: ID) -> String? {
    letters[id].flatMap { firstBooks[$0] == id ? $0 : nil }
  }
}

extension AlphabetIndex where ID == BookID {
  /// `books` must already be in `sort` order.
  package init(books: [Book], sort: LibrarySort) {
    self.init(books, sort: sort, id: \.id, fields: SortFields.init)
  }
}
