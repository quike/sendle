import Foundation
import Observation
import SendleDomain

/// Deleting a book from the Kindle sheet: the question first, then a toast whose Undo puts the
/// book back until its time runs out and the delete becomes final.
@Observable @MainActor
public final class KindleRemovalModel {
  package enum Stage: Hashable, Sendable { case idle, confirming, deleting }

  package private(set) var stage = Stage.idle
  /// Why the last delete didn't happen, shown under the sheet's fields.
  package private(set) var failure: String?
  /// The delete Undo can take back, while its toast shows.
  package private(set) var toast: HeldBook?
  /// The toast's delete, from when its time runs out until it is final.
  private var finalizing: HeldBook?
  /// Told when the toast's time runs out and its delete becomes final.
  @ObservationIgnored package var onFinal: (@MainActor () async -> Void)?

  private let removals: KindleRemovals
  private let sleep: @Sendable (Duration) async -> Void
  @ObservationIgnored private var timer: Task<Void, Never>?

  public convenience init(removals: KindleRemovals) {
    self.init(removals: removals, sleep: { try? await Task.sleep(for: $0) })
  }

  package init(removals: KindleRemovals, sleep: @escaping @Sendable (Duration) async -> Void) {
    self.removals = removals
    self.sleep = sleep
  }

  /// A delete Undo could still take back, one under way, or one still becoming final.
  package var isPending: Bool { toast != nil || stage == .deleting || finalizing != nil }

  package func ask() {
    guard stage == .idle else { return }
    failure = nil
    stage = .confirming
  }

  package func cancel() {
    if stage == .confirming { stage = .idle }
  }

  /// The sheet closed. A delete already under way still finishes.
  package func reset() {
    cancel()
    failure = nil
  }

  /// The toast's delete, if any, becomes final first, even when this one fails.
  package func delete(
    _ book: KindleBook, listedWith listing: [KindleBook], on volume: KindleVolume
  ) async -> KindleRemovalError? {
    stage = .deleting
    failure = nil
    stopTimer()
    defer { stage = .idle }
    do throws(KindleRemovalError) {
      let held = try await removals.delete(book, listedWith: listing, on: volume)
      showToast(for: held)
      return nil
    } catch {
      toast = nil
      failure = Self.failure(error, deleting: book)
      return error
    }
  }

  /// A failed Undo keeps the toast and its time.
  package func undo() async -> KindleRemovalError? {
    guard let held = toast else { return nil }
    do throws(KindleRemovalError) {
      try await removals.undo(held)
    } catch {
      return error
    }
    if toast == held {
      stopTimer()
      toast = nil
    }
    return nil
  }

  /// Its callers read the Kindle themselves or are letting it go, so `onFinal` isn't told.
  package func finalizeNow() async {
    stopTimer()
    await removals.finalizePending()
    toast = nil
  }

  package func clearLeftovers(on volume: KindleVolume) async {
    await removals.clearLeftovers(on: volume)
  }

  private func showToast(for held: HeldBook) {
    toast = held
    timer = Task { [weak self, sleep] in
      await sleep(KindleRemovals.undoWindow)
      guard !Task.isCancelled else { return }
      await self?.toastEnded(held)
    }
  }

  /// The toast goes first, so an Undo can't be offered for a delete becoming final.
  private func toastEnded(_ held: HeldBook) async {
    guard toast == held else { return }
    toast = nil
    finalizing = held
    await removals.finalize(held)
    if finalizing == held { finalizing = nil }
    guard !Task.isCancelled else { return }
    await onFinal?()
  }

  private func stopTimer() {
    timer?.cancel()
    timer = nil
  }

  private static func failure(_ error: KindleRemovalError, deleting book: KindleBook) -> String? {
    switch error {
    case .changedSinceListed:
      "This book changed on the Kindle since Sendle read it. Sendle has read the Kindle again; "
        + "try again if you still want to delete it."
    case .deviceDisconnected:
      nil
    case .occupied, .failed:
      "Couldn't delete \"\(book.title)\": \(error.detail)."
    }
  }
}
