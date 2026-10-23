import SendleDomain

package enum LibraryFilter: String, CaseIterable, Sendable {
  case all
  case notSent
  case onKindle
  case notOnKindle
  case hidden

  package var title: String {
    switch self {
    case .all: "All"
    case .notSent: "Not sent"
    case .onKindle: "On Kindle"
    case .notOnKindle: "Not on Kindle"
    case .hidden: "Hidden"
    }
  }

  /// The scopes that only make sense while a Kindle's books are known.
  var needsKindle: Bool { self == .onKindle || self == .notOnKindle }

  func includes(_ book: Book, wasSent: Bool, onKindle: MatchConfidence?, isHidden: Bool) -> Bool {
    switch self {
    case .all: !isHidden
    case .notSent: !isHidden && !wasSent
    case .onKindle: !isHidden && onKindle != nil
    case .notOnKindle: !isHidden && onKindle == nil
    case .hidden: isHidden
    }
  }
}
