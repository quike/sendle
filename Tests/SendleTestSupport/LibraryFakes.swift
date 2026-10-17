import Foundation
import SendleDomain
import os

public final class FakeBooksLibrary: BooksLibrary {
  private struct State {
    var result: Result<[Book], LibraryError>
    var canWatch = true
    var loads = 0
    var inFlight = 0
    var maxConcurrentLoads = 0
    var gate: Signal?
  }

  private let state: OSAllocatedUnfairLock<State>
  private let changeFeed = Broadcast<Void>()

  public init(_ result: Result<[Book], LibraryError>) {
    state = OSAllocatedUnfairLock(initialState: State(result: result))
  }

  /// What the next `books()` call returns.
  public var result: Result<[Book], LibraryError> {
    get { state.withLock { $0.result } }
    set { state.withLock { $0.result = newValue } }
  }

  /// False makes `changes()` end at once, as the real library does when it can't watch its folder.
  public var canWatch: Bool {
    get { state.withLock { $0.canWatch } }
    set { state.withLock { $0.canWatch = newValue } }
  }

  /// While set, `books()` waits for it to fire before answering.
  public var gate: Signal? {
    get { state.withLock { $0.gate } }
    set { state.withLock { $0.gate = newValue } }
  }

  public var loads: Int { state.withLock { $0.loads } }
  /// The most `books()` calls that were in flight at the same time.
  public var maxConcurrentLoads: Int { state.withLock { $0.maxConcurrentLoads } }
  public var changeSubscribers: Int { changeFeed.subscriberCount }

  public func books() async throws(LibraryError) -> [Book] {
    let (result, gate) = state.withLock { state in
      state.loads += 1
      state.inFlight += 1
      state.maxConcurrentLoads = max(state.maxConcurrentLoads, state.inFlight)
      return (state.result, state.gate)
    }
    if let gate { await gate.wait() }
    state.withLock { $0.inFlight -= 1 }
    return try result.get()
  }

  public func changes() -> AsyncStream<Void> {
    guard canWatch else { return AsyncStream { $0.finish() } }
    return changeFeed.stream()
  }

  public func announceChange() {
    changeFeed.send(())
  }
}

public struct StubProtectionInspector: ProtectionInspector {
  public var protectedIDs: Set<BookID>

  public init(protectedIDs: Set<BookID> = []) {
    self.protectedIDs = protectedIDs
  }

  public func isProtected(_ book: Book) -> Bool {
    protectedIDs.contains(book.id)
  }
}

public final class FakeCoverProvider: CoverProvider {
  public struct Request: Hashable, Sendable {
    public let id: BookID
    public let maxPixel: Int

    public init(id: BookID, maxPixel: Int) {
      self.id = id
      self.maxPixel = maxPixel
    }
  }

  private let covers: [BookID: Data]
  private let unreadable: Set<BookID>
  private let gate: Signal?
  private let log = OSAllocatedUnfairLock<[Request]>(initialState: [])

  /// With a `gate`, every request waits for it to fire. Books in neither `covers` nor
  /// `unreadable` have no cover.
  public init(_ covers: [BookID: Data] = [:], unreadable: Set<BookID> = [], gate: Signal? = nil) {
    self.covers = covers
    self.unreadable = unreadable
    self.gate = gate
  }

  public var requests: [Request] { log.withLock { $0 } }

  public func cover(for book: Book, maxPixel: Int) async -> Cover {
    log.withLock { $0.append(Request(id: book.id, maxPixel: maxPixel)) }
    if let gate { await gate.wait() }
    if let png = covers[book.id] { return .image(png) }
    return unreadable.contains(book.id) ? .unreadable : .none
  }
}

extension Cover {
  public var png: Data? {
    if case .image(let png) = self { png } else { nil }
  }
}
