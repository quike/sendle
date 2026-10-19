import Foundation
import SendleDomain

package enum KindleScope: CaseIterable, Sendable {
  case all
  case fromSendle
  case notInLibrary

  package var title: String {
    switch self {
    case .all: "All"
    case .fromSendle: "From Sendle"
    case .notInLibrary: "Not in Library"
    }
  }
}

extension KindleBookSource {
  package var label: String {
    switch self {
    case .sendle: "From Sendle"
    case .calibre: "From calibre"
    case .amazon: "From Amazon"
    case .email: "Sent by email"
    case .byHand: "Copied by hand"
    }
  }
}

/// One book on the Kindle as every layout shows it.
package struct KindleItemViewModel: Identifiable, Hashable, Sendable {
  package let book: KindleBook
  package let title: String
  package let byline: String
  package let badge: String
  /// Size and where the book came from.
  package let detail: String
  /// What hovering shows: the title, the file and when it was copied.
  package let help: String
  /// Whether a library book matches it, and how surely.
  package let inLibrary: MatchConfidence?

  package var id: KindleBookID { book.id }

  init(book: KindleBook, inLibrary: MatchConfidence?) {
    self.book = book
    self.inLibrary = inLibrary
    title = book.title
    byline = book.authors.isEmpty ? "Unknown author" : book.authors.joined(separator: ", ")
    badge = book.format.uppercased()
    detail = "\(Formatting.size(book.byteCount)) · \(book.source.label)"
    help = [
      "\(title) · \(byline)", "\(badge) · \(detail)", "documents/\(book.id.relativePath)",
      "Copied \(Formatting.day(book.modified))",
    ].joined(separator: "\n")
  }
}

package enum KindleItems {
  /// The books a scope, format and search show, newest file first.
  package static func make(
    books: [KindleBook],
    matches: KindleMatches?,
    scope: KindleScope,
    format: String?,
    query: String
  ) -> [KindleItemViewModel] {
    let words = query.split(whereSeparator: \.isWhitespace)
    return
      books
      .filter { book in
        (format == nil || book.format == format) && includes(book, in: scope, matches: matches)
          && TextMatches.contains(
            every: words, in: ([book.title] + book.authors).joined(separator: " "))
      }
      .sorted {
        $0.modified != $1.modified
          ? $0.modified > $1.modified : $0.id.relativePath < $1.id.relativePath
      }
      .map { KindleItemViewModel(book: $0, inLibrary: matches?.onKindle[$0.id]) }
  }

  private static func includes(
    _ book: KindleBook, in scope: KindleScope, matches: KindleMatches?
  ) -> Bool {
    switch scope {
    case .all: true
    case .fromSendle: book.source == .sendle
    case .notInLibrary: matches?.onKindle[book.id] == nil
    }
  }
}
