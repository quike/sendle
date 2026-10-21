import Foundation
import SendleDomain
import os

/// Holds nothing on disk: it records every call, including the ones it was made to fail.
public final class FakeKindleBookRemover: KindleBookRemover {
  public enum Event: Hashable, Sendable {
    case held(KindleBook)
    case restored(UUID)
    case finalized(UUID)
  }

  private struct State {
    var events: [Event] = []
    var listings: [[KindleBook]] = []
    var clearedVolumes: [KindleVolume] = []
    var parts: [HeldPart] = [.book]
    var leftovers = 0
    var gate: Signal?
    var holdFailure: KindleRemovalError?
    var restoreFailure: KindleRemovalError?
    var finalizeFailure: KindleRemovalError?
  }

  private let state = OSAllocatedUnfairLock(initialState: State())

  public init() {}

  /// Holds, restores and finalizations in the order they were asked for.
  public var events: [Event] { state.withLock { $0.events } }

  public var holds: [KindleBook] {
    events.compactMap { if case .held(let book) = $0 { book } else { nil } }
  }

  /// The listing each hold was given.
  public var listings: [[KindleBook]] { state.withLock { $0.listings } }

  public var restored: [UUID] {
    events.compactMap { if case .restored(let id) = $0 { id } else { nil } }
  }

  public var finalized: [UUID] {
    events.compactMap { if case .finalized(let id) = $0 { id } else { nil } }
  }

  public var clearedVolumes: [KindleVolume] { state.withLock { $0.clearedVolumes } }

  /// The parts each held book reports.
  public var parts: [HeldPart] {
    get { state.withLock { $0.parts } }
    set { state.withLock { $0.parts = newValue } }
  }

  /// What `clearLeftovers` reports.
  public var leftovers: Int {
    get { state.withLock { $0.leftovers } }
    set { state.withLock { $0.leftovers = newValue } }
  }

  /// While set, a hold, restore or finalize is recorded and then waits for it to fire.
  public var gate: Signal? {
    get { state.withLock { $0.gate } }
    set { state.withLock { $0.gate = newValue } }
  }

  public func failHold(with error: KindleRemovalError) {
    state.withLock { $0.holdFailure = error }
  }

  public func failRestore(with error: KindleRemovalError) {
    state.withLock { $0.restoreFailure = error }
  }

  public func failFinalize(with error: KindleRemovalError) {
    state.withLock { $0.finalizeFailure = error }
  }

  public func hold(_ book: KindleBook, listedWith listing: [KindleBook], on volume: KindleVolume)
    async throws(KindleRemovalError) -> HeldBook
  {
    let (failure, parts, gate) = state.withLock { state in
      state.events.append(.held(book))
      state.listings.append(listing)
      return (state.holdFailure, state.parts, state.gate)
    }
    await gate?.wait()
    if let failure { throw failure }
    return HeldBook(book: book, volume: volume, parts: parts)
  }

  public func restore(_ held: HeldBook) async throws(KindleRemovalError) {
    let (failure, gate) = state.withLock { state in
      state.events.append(.restored(held.id))
      return (state.restoreFailure, state.gate)
    }
    await gate?.wait()
    if let failure { throw failure }
  }

  public func finalize(_ held: HeldBook) async throws(KindleRemovalError) {
    let (failure, gate) = state.withLock { state in
      state.events.append(.finalized(held.id))
      return (state.finalizeFailure, state.gate)
    }
    await gate?.wait()
    if let failure { throw failure }
  }

  public func clearLeftovers(on volume: KindleVolume) async -> Int {
    state.withLock { state in
      state.clearedVolumes.append(volume)
      return state.leftovers
    }
  }
}
