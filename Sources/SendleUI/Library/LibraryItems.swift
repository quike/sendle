import Foundation
import SendleDomain

package enum LibraryItems {
  /// The books a filter and search show, in the library's order.
  package static func make(
    books: [Book],
    sends: [BookID: SendRecord],
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
          book: $0, lastSend: sends[$0.id], destination: destination,
          converterAvailable: converterAvailable, now: now)
      }
  }

  /// The newest send of each book that may have reached Amazon.
  package static func latestSends(in records: [SendRecord]) -> [BookID: SendRecord] {
    records.filter { $0.outcome == .sent || $0.outcome == .unconfirmed }
      .reduce(into: [:]) { latest, record in
        if latest[record.bookID].map({ $0.date < record.date }) ?? true {
          latest[record.bookID] = record
        }
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
