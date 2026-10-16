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
  package let canSend: Bool

  package var id: BookID { book.id }

  init(
    book: Book,
    lastSend: SendRecord?,
    destination: DestinationKind,
    converterAvailable: Bool,
    now: Date
  ) {
    self.book = book
    title = book.title
    byline = book.author ?? "Unknown author"
    badge = book.isStorePurchase ? "STORE" : book.format.rawValue.uppercased()
    switch FormatPolicy.plan(for: book, to: destination, converterAvailable: converterAvailable) {
    case .blocked(let reason, _):
      detail = ProblemPresenter.problem(for: reason).title
      tone = book.availability == .ready ? .warning : .unavailable
      canSend = false
    case .send:
      if lastSend?.outcome == .unconfirmed {
        detail = "May have been sent · check your Kindle"
        tone = .warning
      } else if let lastSend {
        let how = lastSend.destination == .email ? "Sent by email" : "Sent over USB"
        detail = "\(how) · \(Formatting.age(of: lastSend.date, now: now))"
        tone = .sent
      } else {
        detail = book.sizeBytes.map { Formatting.size($0) } ?? ""
        tone = .plain
      }
      canSend = true
    }
  }
}
