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
  /// The earlier sends VoiceOver can't see as marks, when the detail doesn't already name them.
  package let spokenRoutes: String?
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
    let sentWording = Self.sentWording(of: routes)
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
        detail = "\(sentWording) · \(Formatting.age(of: sends.latest.date, now: now))"
        tone = .sent
      } else {
        detail = book.sizeBytes.map { Formatting.size($0) } ?? ""
        tone = .plain
      }
      canSend = true
    }
    spokenRoutes = routes.isEmpty || tone == .sent ? nil : "\(sentWording) before"
  }

  private static func sentWording(of routes: [DestinationKind]) -> String {
    let ways = routes.map { kind in
      switch kind {
      case .email: "by email"
      case .usb: "over USB"
      }
    }
    return "Sent \(ways.joined(separator: " and "))"
  }
}
