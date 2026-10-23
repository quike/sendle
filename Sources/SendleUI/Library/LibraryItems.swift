import Foundation
import SendleDomain

package struct BookSends: Hashable, Sendable {
  /// The newest send that may have reached the Kindle.
  package let latest: SendRecord
  /// The ways the book was surely sent, in destination order.
  package let routes: [DestinationKind]
}

package enum LibraryItems {
  /// The books a filter and search show, in the library's order.
  package static func make(
    books: [Book],
    sends: [BookID: BookSends],
    hidden: Set<BookID>,
    filter: LibraryFilter,
    format: BookFormat?,
    query: String,
    destination: DestinationKind,
    converterAvailable: Bool,
    kindle: KindleMatches?,
    now: Date
  ) -> [BookItemViewModel] {
    let words = query.split(whereSeparator: \.isWhitespace)
    return
      books
      .filter { book in
        (format == nil || book.format == format)
          && filter.includes(
            book, wasSent: sends[book.id] != nil, onKindle: kindle?.byBook[book.id]?.confidence,
            isHidden: hidden.contains(book.id))
          && matches(book, words)
      }
      .map { book in
        BookItemViewModel(
          book: book, sends: sends[book.id], destination: destination,
          converterAvailable: converterAvailable,
          kindle: presence(of: book, on: kindle), now: now)
      }
  }

  private static func presence(of book: Book, on kindle: KindleMatches?) -> KindlePresence {
    guard let kindle else { return .none }
    return kindle.byBook[book.id].map { .on($0.confidence) } ?? .notOnKindle
  }

  /// What each book's sent and unconfirmed records add up to; books only ever failed have none.
  package static func sendsByBook(in records: [SendRecord]) -> [BookID: BookSends] {
    Dictionary(grouping: records.filter { $0.outcome != .failed }, by: \.bookID)
      .compactMapValues { records in
        guard let latest = records.max(by: { $0.date < $1.date }) else { return nil }
        let sentBy = Set(records.filter { $0.outcome == .sent }.map(\.destination))
        return BookSends(
          latest: latest, routes: DestinationKind.allCases.filter(sentBy.contains))
      }
  }

  /// Every word must appear in the title or the author, ignoring case and accents.
  private static func matches(_ book: Book, _ words: [Substring]) -> Bool {
    let text = [book.title, book.author ?? ""].joined(separator: " ")
    return TextMatches.contains(every: words, in: text)
  }
}
