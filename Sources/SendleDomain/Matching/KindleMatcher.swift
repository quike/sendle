public enum MatchConfidence: Int, Comparable, Hashable, Sendable, Codable {
  case maybe = 1
  case sure = 2

  public static func < (lhs: MatchConfidence, rhs: MatchConfidence) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

/// Why a library book matches a Kindle book. A later case is a stronger reason.
public enum MatchReason: Int, Comparable, Hashable, Sendable {
  case titleOnly = 1
  case titleAndAuthor
  case emailedTitle
  case sendleName
  case sameContent
  case isbn
  case editionKey

  public static func < (lhs: MatchReason, rhs: MatchReason) -> Bool {
    lhs.rawValue < rhs.rawValue
  }

  public var confidence: MatchConfidence {
    self <= .titleAndAuthor ? .maybe : .sure
  }
}

public struct KindleMatch: Hashable, Sendable {
  public let book: KindleBook
  public let confidence: MatchConfidence
  public let reason: MatchReason

  public init(book: KindleBook, confidence: MatchConfidence, reason: MatchReason) {
    self.book = book
    self.confidence = confidence
    self.reason = reason
  }
}

public struct KindleMatches: Hashable, Sendable {
  /// The strongest match of each library book.
  public let byBook: [BookID: KindleMatch]
  /// The strongest confidence any library book gives that Kindle book.
  public let onKindle: [KindleBookID: MatchConfidence]

  public init(byBook: [BookID: KindleMatch], onKindle: [KindleBookID: MatchConfidence]) {
    self.byBook = byBook
    self.onKindle = onKindle
  }

  /// A Kindle with nothing matched. Not named `none`, which clashes with `Optional.none`.
  public static let empty = KindleMatches(byBook: [:], onKindle: [:])
}

extension KindleMatches {
  /// The library book whose strongest match is this Kindle book, or nil when none points at it.
  public func libraryBook(for id: KindleBookID) -> BookID? {
    byBook.filter { $0.value.book.id == id }
      .max { lhs, rhs in
        // The sides of the ID swap so that the smaller ID ranks higher.
        (lhs.value.confidence, lhs.value.reason, rhs.key.rawValue)
          < (rhs.value.confidence, rhs.value.reason, lhs.key.rawValue)
      }?.key
  }
}

/// A library PDF and a Kindle file with the same bytes.
public struct ContentPair: Hashable, Sendable {
  public let book: BookID
  public let kindleBook: KindleBookID

  public init(book: BookID, kindleBook: KindleBookID) {
    self.book = book
    self.kindleBook = kindleBook
  }
}

public enum KindleMatcher {
  /// `editionASINs` holds each library book's edition ASINs, for every copy number.
  public static func matches(
    books: [Book],
    editions: [BookID: Edition],
    editionASINs: [BookID: Set<String>],
    emailed: Set<BookID>,
    sameContent: Set<ContentPair>,
    listing: [KindleBook]
  ) -> KindleMatches {
    let index = Index(listing)
    var byBook: [BookID: KindleMatch] = [:]
    var onKindle: [KindleBookID: MatchConfidence] = [:]
    for book in books {
      let subject = Subject(
        book: book, edition: editions[book.id], asins: editionASINs[book.id] ?? [],
        isEmailed: emailed.contains(book.id), sameContent: sameContent)
      var best: KindleMatch?
      for candidate in index.candidates(for: subject) {
        guard let reason = subject.reason(matching: candidate) else { continue }
        let match = KindleMatch(book: candidate.book, confidence: reason.confidence, reason: reason)
        onKindle[candidate.book.id] = max(onKindle[candidate.book.id] ?? .maybe, match.confidence)
        if best.map({ isStronger(match, than: $0, for: book) }) ?? true { best = match }
      }
      byBook[book.id] = best
    }
    return KindleMatches(byBook: byBook, onKindle: onKindle)
  }

  /// Within one confidence, the copy under the book's own Sendle name wins, so the duplicate
  /// review can offer to replace it.
  private static func isStronger(
    _ match: KindleMatch, than other: KindleMatch, for book: Book
  ) -> Bool {
    if match.confidence != other.confidence { return match.confidence > other.confidence }
    let isOwn = FileNaming.isSendlesCopy(match.book, of: book)
    if isOwn != FileNaming.isSendlesCopy(other.book, of: book) { return isOwn }
    if match.reason != other.reason { return match.reason > other.reason }
    return match.book.id.relativePath < other.book.id.relativePath
  }

  private struct Candidate {
    let book: KindleBook
    let titleKey: String
    /// The emailed file's name, which keeps a title's own " - ".
    let nameKey: String?
    let authors: Set<String>
    let isbn: String?
  }

  /// An edited book is known by the values it shows and by Books' own, since its earlier copy on
  /// the Kindle carries whichever it was sent with.
  private struct Subject {
    let book: Book
    let titleKeys: Set<String>
    let authors: Set<String>
    let isbn: String?
    let sendleStems: Set<String>
    let asins: Set<String>
    let isEmailed: Bool
    let sameContent: Set<ContentPair>

    init(
      book: Book, edition: Edition?, asins: Set<String>, isEmailed: Bool,
      sameContent: Set<ContentPair>
    ) {
      self.book = book
      titleKeys = Set([book.title, book.original.title].map(NameKey.title)).subtracting([""])
      authors = NameKey.authors([book.author, book.original.author].compactMap { $0 })
      isbn = edition?.isbn.flatMap(ISBN.normalised)
      sendleStems = Set([book, book.unedited].map { FileNaming.baseName(for: $0).lowercased() })
      self.asins = asins
      self.isEmailed = isEmailed
      self.sameContent = sameContent
    }

    func reason(matching candidate: Candidate) -> MatchReason? {
      let kindle = candidate.book
      // A placeholder identifier can give unrelated EPUBs one edition key.
      if let asin = kindle.asin, asins.contains(asin),
        titleKeys.contains(candidate.titleKey) || !authors.isDisjoint(with: candidate.authors)
      {
        return .editionKey
      }
      if let isbn, isbn == candidate.isbn { return .isbn }
      if sameContent.contains(ContentPair(book: book.id, kindleBook: kindle.id)) {
        return .sameContent
      }
      if kindle.source == .sendle, kindle.asinFollowsFileName,
        sendleStems.contains(kindle.stem.lowercased())
      {
        return .sendleName
      }
      if isEmailed, kindle.source == .email,
        titleKeys.contains(candidate.titleKey) || candidate.nameKey.map(titleKeys.contains) == true
      {
        return .emailedTitle
      }
      guard titleKeys.contains(candidate.titleKey) else { return nil }
      if !authors.isDisjoint(with: candidate.authors) { return .titleAndAuthor }
      if authors.isEmpty || candidate.authors.isEmpty { return .titleOnly }
      return nil
    }
  }

  /// Kindle books by each key a library book could reach them through, so a match doesn't compare
  /// every pair.
  private struct Index {
    private var byASIN: [String: [Candidate]] = [:]
    private var byISBN: [String: [Candidate]] = [:]
    private var bySendleStem: [String: [Candidate]] = [:]
    private var byTitleKey: [String: [Candidate]] = [:]
    private let byID: [KindleBookID: Candidate]

    init(_ listing: [KindleBook]) {
      var byID: [KindleBookID: Candidate] = [:]
      for book in listing {
        let isEmail = book.source == .email
        let candidate = Candidate(
          book: book,
          titleKey: NameKey.title(book.title),
          nameKey: isEmail ? NameKey.title(KindleFileName.parse(book.id.relativePath).name) : nil,
          authors: NameKey.authors(book.authors),
          isbn: book.isbn.flatMap(ISBN.normalised))
        byID[book.id] = candidate
        if let asin = book.asin { byASIN[asin, default: []].append(candidate) }
        if let isbn = candidate.isbn { byISBN[isbn, default: []].append(candidate) }
        if book.source == .sendle, book.asinFollowsFileName {
          bySendleStem[book.stem.lowercased(), default: []].append(candidate)
        }
        byTitleKey[candidate.titleKey, default: []].append(candidate)
        if let nameKey = candidate.nameKey, nameKey != candidate.titleKey {
          byTitleKey[nameKey, default: []].append(candidate)
        }
      }
      self.byID = byID
    }

    func candidates(for subject: Subject) -> [Candidate] {
      var found: [KindleBookID: Candidate] = [:]
      func add(_ candidates: [Candidate]?) {
        for candidate in candidates ?? [] { found[candidate.book.id] = candidate }
      }
      for asin in subject.asins { add(byASIN[asin]) }
      if let isbn = subject.isbn { add(byISBN[isbn]) }
      for stem in subject.sendleStems { add(bySendleStem[stem]) }
      for key in subject.titleKeys { add(byTitleKey[key]) }
      for pair in subject.sameContent where pair.book == subject.book.id {
        if let candidate = byID[pair.kindleBook] { found[pair.kindleBook] = candidate }
      }
      return Array(found.values)
    }
  }
}
