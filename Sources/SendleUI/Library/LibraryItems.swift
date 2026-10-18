import Foundation
import SendleDomain

package struct BookSends: Hashable, Sendable {
  /// The newest send that may have reached Amazon.
  package let latest: SendRecord
  /// The ways the book was surely sent, in destination order.
  package let routes: [DestinationKind]
}

package enum LibraryItems {
  /// The books a filter and search show, in the library's order.
  package static func make(
    books: [Book],
    sends: [BookID: BookSends],
    filter: LibraryFilter,
    query: String,
    destination: DestinationKind,
    converterAvailable: Bool,
    now: Date
  ) -> [BookItemViewModel] {
    let words = query.split(whereSeparator: \.isWhitespace)
    return
      books
      .filter { filter.includes($0, wasSent: sends[$0.id] != nil) && matches($0, words) }
      .map {
        BookItemViewModel(
          book: $0, sends: sends[$0.id], destination: destination,
          converterAvailable: converterAvailable, now: now)
      }
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
    return words.allSatisfy {
      text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
  }
}
