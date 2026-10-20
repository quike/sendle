import Foundation
import SendleDomain

/// Whether the plugged-in Kindle was read, and what it holds of a book.
package enum KindlePresence: Hashable, Sendable {
  /// No Kindle has been read.
  case none
  case notOnKindle
  case on(MatchConfidence)
}

/// A small symbol on a book: where it was sent, or that it is on the Kindle.
package enum BookMark: Hashable, Sendable {
  case route(DestinationKind, dimmed: Bool)
  case onKindle
  case maybeOnKindle

  package var symbol: String {
    switch self {
    case .route(let kind, _): kind.symbol
    case .onKindle: "ipad"
    case .maybeOnKindle: "questionmark"
    }
  }
}

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
  /// Size, last send, an edit made since, or why the book can't go to the active destination.
  package let detail: String
  package let tone: Tone
  /// Where the book was sent for sure.
  package let routes: [DestinationKind]
  /// The marks to draw: the email route, then whichever of the Kindle or the USB route is known.
  package let marks: [BookMark]
  /// What the plugged-in Kindle says about the book, in words; nil when it has nothing to add.
  package let kindleText: String?
  /// The earlier sends VoiceOver can't see as marks, when the detail doesn't already name them.
  package let spokenRoutes: String?
  package let canSend: Bool
  /// Whether any edit of the user's applies to the book, which the cover marks with a pencil.
  package let isEdited: Bool

  package var id: BookID { book.id }

  init(
    book: Book,
    sends: BookSends?,
    destination: DestinationKind,
    converterAvailable: Bool,
    kindle: KindlePresence,
    now: Date
  ) {
    self.book = book
    title = book.title
    byline = book.author ?? "Unknown author"
    badge = book.isStorePurchase ? "STORE" : book.format.rawValue.uppercased()
    isEdited = book.edits.isEdited
    routes = sends?.routes ?? []
    marks = Self.marks(routes: routes, kindle: kindle)
    kindleText = Self.kindleText(routes: routes, kindle: kindle)
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
      } else if let sends, let changedAt = book.edits.changedAt, changedAt > sends.latest.date {
        detail = "Changed since sent"
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

  private static func marks(routes: [DestinationKind], kindle: KindlePresence) -> [BookMark] {
    var marks: [BookMark] = routes.contains(.email) ? [.route(.email, dimmed: false)] : []
    switch kindle {
    case .on(.sure): marks.append(.onKindle)
    case .on(.maybe): marks.append(.maybeOnKindle)
    case .none, .notOnKindle:
      if routes.contains(.usb) { marks.append(.route(.usb, dimmed: kindle == .notOnKindle)) }
    }
    return marks
  }

  private static func kindleText(routes: [DestinationKind], kindle: KindlePresence) -> String? {
    switch kindle {
    case .on(.sure): "On this Kindle"
    case .on(.maybe): "Maybe on this Kindle · another edition?"
    case .notOnKindle where routes.contains(.usb): "Sent over USB · not on this Kindle"
    case .none, .notOnKindle: nil
    }
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
