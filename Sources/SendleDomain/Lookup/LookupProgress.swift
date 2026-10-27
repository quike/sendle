/// What one source answered. By ISBN `found` holds one edition; by title, the ranked list.
public enum SourceAnswer: Hashable, Sendable {
  case found([FoundEdition])
  case notFound
  case failed(LookupError)

  fileprivate var isFound: Bool {
    if case .found = self { true } else { false }
  }

  fileprivate var isFailed: Bool {
    if case .failed = self { true } else { false }
  }
}

/// What the sheet knows about one source right now.
public enum SourceResult: Hashable, Sendable {
  case asking
  case edition(FoundEdition)
  case editions([FoundEdition])
  case notFound
  case failed(LookupError)
}

public enum LookupMethod: Hashable, Sendable {
  case isbn
  case titleAndAuthor
}

/// The answers a lookup has had so far, and which source and list the sheet should show.
public struct LookupProgress: Hashable, Sendable {
  /// The enabled sources, in the order they are shown.
  public let sources: [LookupSource]
  public var method: LookupMethod
  public var isbnAnswers: [LookupSource: SourceAnswer]
  public var titleAnswers: [LookupSource: SourceAnswer]
  public var isFinished: Bool

  public init(
    sources: [LookupSource],
    method: LookupMethod,
    isbnAnswers: [LookupSource: SourceAnswer] = [:],
    titleAnswers: [LookupSource: SourceAnswer] = [:],
    isFinished: Bool = false
  ) {
    self.sources = sources
    self.method = method
    self.isbnAnswers = isbnAnswers
    self.titleAnswers = titleAnswers
    self.isFinished = isFinished
  }

  public func result(for source: LookupSource) -> SourceResult {
    if case .found(let editions)? = isbnAnswers[source], let edition = editions.first {
      return .edition(edition)
    }
    let answer = method == .titleAndAuthor ? titleAnswers[source] : isbnAnswers[source]
    switch answer {
    case nil: return .asking
    case .found(let editions)?: return editions.isEmpty ? .notFound : .editions(editions)
    case .notFound?: return .notFound
    case .failed(let error)?: return .failed(error)
    }
  }

  /// The first source, in order, that has details to show; nil while an earlier one is still asking.
  public var shownSource: LookupSource? {
    for source in sources {
      switch result(for: source) {
      case .asking: return nil
      case .edition, .editions: return source
      case .notFound, .failed: continue
      }
    }
    return nil
  }

  /// Whether every source has answered the ISBN lookup without a dated edition and not all failed,
  /// so the list of editions is what the user needs.
  public var needsEditionList: Bool {
    guard method == .isbn else { return false }
    let answers = sources.compactMap { isbnAnswers[$0] }
    guard answers.count == sources.count else { return false }
    let datedSourceFound = sources.contains { $0.givesDates && isbnAnswers[$0]?.isFound == true }
    return !datedSourceFound && !answers.allSatisfy(\.isFailed)
  }
}
