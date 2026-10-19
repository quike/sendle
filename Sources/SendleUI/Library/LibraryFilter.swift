import SendleDomain

package enum LibraryFilter: String, CaseIterable, Sendable {
  case all
  case notSent
  case onKindle
  case notOnKindle

  package var title: String {
    switch self {
    case .all: "All"
    case .notSent: "Not sent"
    case .onKindle: "On Kindle"
    case .notOnKindle: "Not on Kindle"
    }
  }

  /// The scopes that only make sense while a Kindle's books are known.
  var needsKindle: Bool { self == .onKindle || self == .notOnKindle }

  func includes(_ book: Book, wasSent: Bool, onKindle: MatchConfidence?) -> Bool {
    switch self {
    case .all: true
    case .notSent: !wasSent
    case .onKindle: onKindle != nil
    case .notOnKindle: onKindle == nil
    }
  }
}
