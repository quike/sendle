import Foundation
import SendleDomain
import os

public final class FakeBooksLibrary: BooksLibrary {
  private struct State {
    var result: Result<[Book], LibraryError>
    var canWatch = true
    var loads = 0
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

  public var loads: Int { state.withLock { $0.loads } }
  public var changeSubscribers: Int { changeFeed.subscriberCount }

  public func books() async throws(LibraryError) -> [Book] {
    try state.withLock { state in
      state.loads += 1
      return state.result
    }.get()
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
