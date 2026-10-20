import Foundation
import Observation
import SendleDomain

package enum KindleState: Equatable, Sendable {
  case idle
  case reading(done: Int, total: Int)
  case loaded
  case failed(Problem)
}

/// What the plugged-in Kindle holds: its listing, how far a read is, and how the library matches it.
@Observable @MainActor
public final class KindleViewModel {
  package private(set) var volume: KindleVolume?
  package private(set) var state = KindleState.idle
  package private(set) var listing: KindleListing? {
    didSet { refreshItems() }
  }
  package private(set) var matches: KindleMatches? {
    didSet { refreshItems() }
  }
  package var query = "" {
    didSet { listChanged(query != oldValue) }
  }
  package var scope = KindleScope.all {
    didSet { listChanged(scope != oldValue) }
  }
  /// A lowercased extension; nil shows every format.
  package var format: String? {
    didSet { listChanged(format != oldValue) }
  }
  /// Shared with the library's sort, which saves it.
  package var sort = LibrarySort.recent {
    didSet { listChanged(sort != oldValue) }
  }
  /// Bumped when a new query, scope, format, sort or Kindle should start at the top of the list.
  package private(set) var scrollToTopRequests = 0
  /// The books the scope, format and search show, in the sort's order.
  package private(set) var items: [KindleItemViewModel] = []
  /// The newest books on screen, whatever the sort, for the shelf.
  package private(set) var recentItems: [KindleItemViewModel] = []
  /// The formats on the Kindle, as lowercased extensions.
  package private(set) var formats: [String] = []
  package let letterJump = LetterJump<KindleBookID>()
  package let covers: KindleCoverStore
  /// Told whenever the library's matches against the Kindle change, nil once there is no Kindle.
  @ObservationIgnored package var onMatchesChange: (@MainActor (KindleMatches?) -> Void)?

  private var books: [Book] = []
  /// Reads and matches run one after another, so a slow older one can't replace a newer one.
  @ObservationIgnored private var queue: Task<Void, Never>?
  /// The queued work, so a Kindle that goes can cancel what is matching it.
  @ObservationIgnored private var queued: [UUID: Task<Void, Never>] = [:]
  /// A read is queued and hasn't started, so asking for another adds nothing.
  @ObservationIgnored private var isReadQueued = false
  @ObservationIgnored private var reading: Task<Result<KindleListing, KindleListingError>, Never>?
  /// Changes with each Kindle followed, so work for one that went is dropped.
  @ObservationIgnored private var epoch = 0
  /// Why the last read failed.
  @ObservationIgnored private var failure: KindleListingError?

  private let library: any KindleLibrary
  private let match: MatchKindleBooks

  public init(library: any KindleLibrary, match: MatchKindleBooks) {
    self.library = library
    self.match = match
    covers = KindleCoverStore(library: library)
  }

  package var subtitle: String {
    let name = volume?.name ?? "Kindle"
    switch state {
    case .idle:
      return name
    case .failed:
      return "Couldn't read \(name)"
    case .reading(let done, let total):
      return total == 0 ? "Reading \(name)…" : "Reading \(name)… \(done) of \(total)"
    case .loaded:
      guard let listing else { return name }
      let count = listing.books.count
      let free = listing.freeBytes.map { " · \(ByteCount.text($0)) free" } ?? ""
      return "\(name) · \(count) \(count == 1 ? "book" : "books")\(free)"
    }
  }

  /// A new Kindle is read; the same one is only matched again when the library's books changed.
  package func follow(_ volume: KindleVolume?, books: [Book]) async {
    let libraryChanged = books != self.books
    self.books = books
    guard let volume else { return forget() }
    if volume != self.volume {
      forget()
      self.volume = volume
      await queueRead()
    } else if libraryChanged, listing != nil {
      await rematch()
    }
  }

  /// Reads the Kindle again, after the read in progress if there is one.
  package func refresh() async {
    guard volume != nil, !isReadQueued else { return }
    await queueRead()
  }

  /// Which of `books` the Kindle at `volume` already holds, read afresh so a book copied in since
  /// the last read still counts. A Kindle this model doesn't follow is read on the side.
  package func duplicates(of books: [Book], on volume: KindleVolume) async -> DuplicateCheck {
    let found: Result<(KindleListing, KindleMatches), KindleListingError>
    if volume == self.volume {
      let epoch = epoch
      await refresh()
      await queue?.value
      guard epoch == self.epoch else { return .interrupted }
      if case .loaded = state, let listing, let matches {
        found = .success((listing, matches))
      } else {
        found = .failure(failure ?? .cancelled)
      }
    } else {
      found = await readAside(volume, matching: books)
    }
    switch found {
    case .failure(let error):
      return .unreadable(error)
    case .success(let (listing, matches)):
      return .checked(await duplicateCases(of: books, in: matches), in: listing)
    }
  }

  /// `copies`, with each copy moved to an ASIN that no file in `listing` and no other book has.
  package func plannedCopies(
    for books: [Book], copies: [BookID: KindleCopy], listing: [KindleBook]
  ) async -> [BookID: KindleCopy] {
    await match.plannedCopies(books, copies: copies, listing: listing)
  }

  /// Matches the library against the listing already read.
  package func rematch() async {
    guard listing != nil else { return }
    await enqueue { await $0.matchLibrary() }
  }

  // MARK: Private

  private func readAside(
    _ volume: KindleVolume, matching books: [Book]
  ) async -> Result<(KindleListing, KindleMatches), KindleListingError> {
    do throws(KindleListingError) {
      let listing = try await library.listing(of: volume) { _, _ in }
      return .success((listing, await match(books, against: listing.books, on: volume)))
    } catch {
      return .failure(error)
    }
  }

  private func duplicateCases(of books: [Book], in matches: KindleMatches) async -> [DuplicateCase]
  {
    var found: [(book: Book, match: KindleMatch)] = []
    for book in books {
      if let match = matches.byBook[book.id] { found.append((book, match)) }
    }
    // Only EPUBs on this Mac have an edition, and reading one must not download it.
    let readable = found.map(\.book).filter(Self.hasReadableEdition)
    var editions: [BookID: Edition] = [:]
    if !readable.isEmpty { editions = await match.editions(of: readable) }
    return found.map { entry in
      DuplicateCase(
        book: entry.book, edition: editions[entry.book.id], match: entry.match,
        replace: FileNaming.isSendlesCopy(entry.match.book, of: entry.book)
          ? .inPlace : .unavailable)
    }
  }

  private func listChanged(_ changed: Bool) {
    if changed { scrollToTop() }
    refreshItems()
  }

  private func scrollToTop() {
    letterJump.top = nil
    scrollToTopRequests += 1
  }

  /// Rebuilds what the layouts show; a format that left with its books is dropped.
  private func refreshItems() {
    formats = Set((listing?.books ?? []).map(\.format).filter { !$0.isEmpty }).sorted()
    if let format, !formats.contains(format) {
      self.format = nil
      return
    }
    let newestFirst = KindleItems.make(
      books: listing?.books ?? [], matches: matches, scope: scope, format: format, query: query)
    items = LibraryOrder.sorted(newestFirst, by: sort, fields: SortFields.init)
    recentItems = Array(newestFirst.prefix(8))
    letterJump.index =
      sort == .recent ? nil : AlphabetIndex(items, sort: sort, id: \.id, fields: SortFields.init)
  }

  private func forget() {
    epoch += 1
    reading?.cancel()
    queued.values.forEach { $0.cancel() }
    isReadQueued = false
    scrollToTop()
    covers.reset()
    volume = nil
    listing = nil
    state = .idle
    clearMatches()
  }

  private func clearMatches() {
    guard matches != nil else { return }
    setMatches(nil)
  }

  private func queueRead() async {
    isReadQueued = true
    await enqueue {
      $0.isReadQueued = false
      await $0.read()
    }
  }

  private func enqueue(_ work: @escaping @MainActor (KindleViewModel) async -> Void) async {
    let previous = queue
    let epoch = epoch
    let id = UUID()
    let next = Task { [weak self] in
      await previous?.value
      guard let self, self.epoch == epoch else { return }
      await work(self)
    }
    queue = next
    queued[id] = next
    await next.value
    queued[id] = nil
  }

  private func read() async {
    guard let volume else { return }
    let epoch = epoch
    let before = state
    state = .reading(done: 0, total: 0)
    let library = library
    let task = Task { [weak self] () -> Result<KindleListing, KindleListingError> in
      do throws(KindleListingError) {
        return .success(
          try await library.listing(of: volume) { [weak self] done, total in
            await self?.report(done: done, total: total, epoch: epoch)
          })
      } catch {
        return .failure(error)
      }
    }
    reading = task
    let result = await task.value
    guard epoch == self.epoch else { return }
    if case .failure(let error) = result { failure = error } else { failure = nil }
    switch result {
    case .success(let listing):
      self.listing = listing
      state = .loaded
      await matchLibrary()
    case .failure(.cancelled):
      state = before
    case .failure(let error):
      listing = nil
      clearMatches()
      state = .failed(Self.problem(for: error, on: volume))
    }
  }

  private func report(done: Int, total: Int, epoch: Int) {
    guard epoch == self.epoch, case .reading = state else { return }
    state = .reading(done: done, total: total)
  }

  private func matchLibrary() async {
    guard let volume, let listing else { return }
    let epoch = epoch
    let found = await match(books, against: listing.books, on: volume)
    guard epoch == self.epoch else { return }
    setMatches(found)
  }

  private func setMatches(_ matches: KindleMatches?) {
    self.matches = matches
    onMatchesChange?(matches)
  }

  private static func hasReadableEdition(_ book: Book) -> Bool {
    guard book.format == .epub else { return false }
    return book.availability == .ready || book.availability == .protected
  }

  private static func problem(for error: KindleListingError, on volume: KindleVolume) -> Problem {
    switch error {
    case .deviceDisconnected:
      Problem("\(volume.name) was unplugged", message: "Plug it in again to see its books.")
    case .unreadable(let detail):
      Problem(
        "Couldn't read \(volume.name)", message: detail, fix: Fix("Try again", .retry))
    case .cancelled:
      Problem("Couldn't read \(volume.name)")
    }
  }
}
