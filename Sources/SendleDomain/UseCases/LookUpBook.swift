import Foundation

/// Looks a book up in every enabled catalogue at once, and keeps their answers for the app's run.
public struct LookUpBook: Sendable {
  private let catalogues: [LookupSource: any BookCatalogue]
  private let settings: any SettingsStore
  private let log: any ActivityLog
  private let deadline: Duration
  private let cache = AnswerCache()

  /// A catalogue that takes longer than `deadline` to answer a question has timed out.
  public init(
    catalogues: [any BookCatalogue], settings: any SettingsStore,
    log: any ActivityLog = NoActivityLog(), deadline: Duration = .seconds(10)
  ) {
    self.catalogues = Dictionary(
      catalogues.map { ($0.source, $0) }, uniquingKeysWith: { first, _ in first })
    self.settings = settings
    self.log = log
    self.deadline = deadline
  }

  /// The catalogues' sources, in order.
  public var available: [LookupSource] { catalogues.keys.sorted() }

  /// Asks the enabled sources by ISBN, then by title and author when no source with dates knows
  /// the ISBN, and reports after each answer. Refreshing asks every source again instead of
  /// answering from the cache. Ending the stream stops the lookup.
  public func lookUp(
    _ query: LookupQuery, refreshing: Bool = false
  ) -> AsyncStream<LookupProgress> {
    let (stream, continuation) = AsyncStream.makeStream(of: LookupProgress.self)
    let task = Task {
      await search(query, refreshing: refreshing, reporting: continuation)
      continuation.finish()
    }
    continuation.onTermination = { _ in task.cancel() }
    return stream
  }

  /// What the edition's catalogue has under its ISBN, or the edition as it is when that gives
  /// nothing.
  public func refine(_ edition: FoundEdition) async -> FoundEdition {
    guard let isbn = edition.isbn, let catalogue = catalogues[edition.source] else {
      return edition
    }
    let reply = await answer(to: .isbn(isbn), from: catalogue)
    record(reply, from: edition.source, by: .isbn)
    guard case .found(let editions) = reply, let refined = editions.first else { return edition }
    return refined
  }

  /// Nil when the source has no catalogue or it fails.
  public func image(at url: URL, from source: LookupSource) async -> Data? {
    try? await catalogues[source]?.image(at: url)
  }

  private func search(
    _ query: LookupQuery, refreshing: Bool,
    reporting continuation: AsyncStream<LookupProgress>.Continuation
  ) async {
    let enabled = await settings.load().lookupSources
    var progress = LookupProgress(
      sources: available.filter(enabled.contains),
      method: query.isbn == nil ? .titleAndAuthor : .isbn)
    if let isbn = query.isbn {
      progress = await ask(by: .isbn, progress, reporting: continuation) { catalogue in
        let reply = await self.answer(to: .isbn(isbn), from: catalogue, refreshing: refreshing)
        return Self.checked(reply, from: catalogue.source, for: query)
      }
      guard !Task.isCancelled else { return }
      if progress.needsEditionList {
        progress.method = .titleAndAuthor
        continuation.yield(progress)
      }
    }
    if progress.method == .titleAndAuthor {
      let question = Question.title(query.title, author: query.author, language: query.language)
      progress = await ask(by: .titleAndAuthor, progress, reporting: continuation) { catalogue in
        await self.answer(to: question, from: catalogue, refreshing: refreshing)
      }
      guard !Task.isCancelled else { return }
    }
    progress.isFinished = true
    continuation.yield(progress)
  }

  /// Asks each of `progress`'s sources at once, and yields `progress` with each answer as it comes.
  private func ask(
    by method: LookupMethod, _ progress: LookupProgress,
    reporting continuation: AsyncStream<LookupProgress>.Continuation,
    _ answering: @escaping @Sendable (any BookCatalogue) async -> SourceAnswer
  ) async -> LookupProgress {
    let answers: WritableKeyPath<LookupProgress, [LookupSource: SourceAnswer]> =
      method == .isbn ? \.isbnAnswers : \.titleAnswers
    return await withTaskGroup(of: (LookupSource, SourceAnswer).self) { group in
      for source in progress.sources {
        guard let catalogue = catalogues[source] else { continue }
        _ = group.addTaskUnlessCancelled { (source, await answering(catalogue)) }
      }
      var progress = progress
      for await (source, reply) in group {
        guard !Task.isCancelled else { break }
        record(reply, from: source, by: method)
        progress[keyPath: answers][source] = reply
        continuation.yield(progress)
      }
      return progress
    }
  }

  /// By ISBN the edition, by title the editions ranked; Google Books' terms keep its own order.
  private func answer(
    to question: Question, from catalogue: any BookCatalogue, refreshing: Bool = false
  ) async -> SourceAnswer {
    do throws(LookupError) {
      let found = try await editions(for: question, from: catalogue, refreshing: refreshing)
      switch question {
      case .isbn:
        return found.first.map { .found([$0]) } ?? .notFound
      case .title where catalogue.source == .googleBooks:
        return .found(Array(found.prefix(EditionOrder.limit)))
      case .title(_, _, let language):
        return .found(EditionOrder.ranked(found, language: language))
      }
    } catch {
      return .failed(error)
    }
  }

  /// At most one edition by ISBN; from the cache when the question was asked before, unless
  /// refreshing.
  private func editions(
    for question: Question, from catalogue: any BookCatalogue, refreshing: Bool
  ) async throws(LookupError) -> [FoundEdition] {
    if !refreshing, let kept = await cache.editions(for: question, from: catalogue.source) {
      return kept
    }
    let found = try await withinDeadline { () async throws(LookupError) -> [FoundEdition] in
      switch question {
      case .isbn(let isbn):
        try await catalogue.edition(isbn: isbn).map { [$0] } ?? []
      case .title(let title, let author, let language):
        try await catalogue.editions(title: title, author: author, language: language)
      }
    }
    await cache.keep(found, for: question, from: catalogue.source)
    return found
  }

  /// What `asking` answers, or `.timedOut` once the deadline passes, which cancels it.
  private func withinDeadline(
    _ asking: @escaping @Sendable () async throws(LookupError) -> [FoundEdition]
  ) async throws(LookupError) -> [FoundEdition] {
    let deadline = deadline
    let answer = await withTaskGroup(of: Result<[FoundEdition], LookupError>?.self) { group in
      group.addTask {
        do throws(LookupError) {
          return .success(try await asking())
        } catch {
          return .failure(error)
        }
      }
      group.addTask {
        // Cancelled, the clock leaves the answer to the catalogue.
        guard (try? await Task.sleep(for: deadline)) != nil else { return nil }
        return .failure(.timedOut)
      }
      defer { group.cancelAll() }
      for await answer in group {
        if let answer { return answer }
      }
      return .failure(.timedOut)
    }
    return try answer.get()
  }

  private func record(_ reply: SourceAnswer, from source: LookupSource, by method: LookupMethod) {
    let asked = "\(source.name) by \(method == .isbn ? "ISBN" : "title and author")"
    switch reply {
    case .found(let editions) where method == .titleAndAuthor:
      let count = editions.count
      log.info(.lookup, "\(asked): \(count) \(count == 1 ? "edition" : "editions")")
    case .found:
      log.info(.lookup, "\(asked): found")
    case .notFound:
      log.info(.lookup, "\(asked): didn't find it")
    case .failed(let error):
      log.warning(.lookup, "\(asked): \(error.logDescription)")
    }
  }

  /// Apple's ISBN lookup can answer with an unrelated book, so its edition counts only when it
  /// is the query's.
  private static func checked(
    _ reply: SourceAnswer, from source: LookupSource, for query: LookupQuery
  ) -> SourceAnswer {
    guard source == .appleBooks, case .found(let editions) = reply, let edition = editions.first
    else { return reply }
    return isBook(of: query, edition) ? reply : .notFound
  }

  /// The title matches, or the part before a series or subtitle does, and an author is shared;
  /// a query without an author needs only the title.
  private static func isBook(of query: LookupQuery, _ edition: FoundEdition) -> Bool {
    guard let title = edition.title else { return false }
    let cut = [title.range(of: " (")?.lowerBound, title.firstIndex(of: ":")].compactMap { $0 }.min()
    let titles = [title, cut.map { String(title[..<$0]) }].compactMap { $0 }.map(NameKey.title)
    guard titles.contains(NameKey.title(query.title)) else { return false }
    guard let author = query.author else { return true }
    guard let found = edition.author else { return false }
    return !NameKey.authors([author]).isDisjoint(with: NameKey.authors([found]))
  }
}

/// What a lookup asks one catalogue.
private enum Question: Hashable, Sendable {
  case isbn(String)
  case title(String, author: String?, language: String?)
}

/// Every source's answers to the questions it was asked. Failures are not kept, so they are
/// asked again.
private actor AnswerCache {
  private var answers: [LookupSource: [Question: [FoundEdition]]] = [:]

  func editions(for question: Question, from source: LookupSource) -> [FoundEdition]? {
    answers[source]?[question]
  }

  func keep(_ editions: [FoundEdition], for question: Question, from source: LookupSource) {
    answers[source, default: [:]][question] = editions
  }
}
