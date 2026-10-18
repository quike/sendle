import Foundation
import SendleDomain

/// One book as every layout shows it.
package struct BookItemViewModel: Identifiable, Hashable, Sendable {
  package enum Tone: Sendable {
    case plain
    case sent
    case warning
    case unavailable
  }

  package let book: Book
  package let title: String
  package let byline: String
  package let badge: String
  /// Size, last send, or why the book can't go to the active destination.
  package let detail: String
  package let tone: Tone
  /// Where the book was sent for sure.
  package let routes: [DestinationKind]
  package let canSend: Bool

  package var id: BookID { book.id }

  init(
    book: Book,
    sends: BookSends?,
    destination: DestinationKind,
    converterAvailable: Bool,
    now: Date
  ) {
    self.book = book
    title = book.title
    byline = book.author ?? "Unknown author"
    badge = book.isStorePurchase ? "STORE" : book.format.rawValue.uppercased()
    routes = sends?.routes ?? []
    switch FormatPolicy.plan(for: book, to: destination, converterAvailable: converterAvailable) {
    case .blocked(let reason, _):
      detail = ProblemPresenter.problem(for: reason).title
      tone = book.availability == .ready ? .warning : .unavailable
      canSend = false
    case .send:
      if sends?.latest.outcome == .unconfirmed {
        detail = "May have been sent · check your Kindle"
        tone = .warning
      } else if let sends {
        let how = sends.routes.map { $0 == .email ? "by email" : "over USB" }
          .joined(separator: " and ")
        detail = "Sent \(how) · \(Formatting.age(of: sends.latest.date, now: now))"
        tone = .sent
      } else {
        detail = book.sizeBytes.map { Formatting.size($0) } ?? ""
        tone = .plain
      }
      canSend = true
    }
  }
}
