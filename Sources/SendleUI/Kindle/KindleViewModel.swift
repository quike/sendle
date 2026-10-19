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
  package private(set) var listing: KindleListing?
  package private(set) var matches: KindleMatches?
  /// Told whenever the library's matches against the Kindle change, nil once there is no Kindle.
  @ObservationIgnored package var onMatchesChange: (@MainActor (KindleMatches?) -> Void)?

  private var books: [Book] = []
  /// Reads and matches run one after another, so a slow older one can't replace a newer one.
  @ObservationIgnored private var queue: Task<Void, Never>?
  @ObservationIgnored private var reading: Task<Result<KindleListing, KindleListingError>, Never>?
  /// Changes with each Kindle followed, so work for one that went is dropped.
  @ObservationIgnored private var epoch = 0

  private let library: any KindleLibrary
  private let match: MatchKindleBooks

  public init(library: any KindleLibrary, match: MatchKindleBooks) {
    self.library = library
    self.match = match
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
      await enqueue { await $0.read() }
    } else if libraryChanged, listing != nil {
      await rematch()
    }
  }

  /// Reads the Kindle again, after the read in progress if there is one.
  package func refresh() async {
    guard volume != nil else { return }
    await enqueue { await $0.read() }
  }

  /// Matches the library against the listing already read.
  package func rematch() async {
    guard listing != nil else { return }
    await enqueue { await $0.matchLibrary() }
  }

  // MARK: Private

  private func forget() {
    epoch += 1
    reading?.cancel()
    volume = nil
    listing = nil
    state = .idle
    clearMatches()
  }

  private func clearMatches() {
    guard matches != nil else { return }
    setMatches(nil)
  }

  private func enqueue(_ work: @escaping @MainActor (KindleViewModel) async -> Void) async {
    let previous = queue
    let epoch = epoch
    let next = Task { [weak self] in
      await previous?.value
      guard let self, self.epoch == epoch else { return }
      await work(self)
    }
    queue = next
    await next.value
  }

  private func read() async {
    guard let volume else { return }
    let epoch = epoch
    let before = state
    state = .reading(done: 0, total: 0)
    let library = library
    let task = Task { () -> Result<KindleListing, KindleListingError> in
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
