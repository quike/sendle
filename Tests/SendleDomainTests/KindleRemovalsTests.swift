import Foundation
import SendleDomain
import SendleTestSupport
import Testing

@Suite(.timeLimit(.minutes(1)))
struct KindleRemovalsTests {
  let remover = FakeKindleBookRemover()
  let log = FakeActivityLog()
  let removals: KindleRemovals
  let book = KindleBook.fixture()
  let other = KindleBook.fixture(path: "Dune - Frank Herbert.azw3")

  init() {
    removals = KindleRemovals(remover: remover, log: log)
  }

  @Test func aDeleteIsHeldAndPending() async throws {
    let held = try await removals.delete(book, listedWith: [book], on: .fixture())

    #expect(remover.holds == [book])
    #expect(remover.listings == [[book]])
    #expect(await removals.pending == held)
    #expect(
      log.messages(in: .usb)
        == ["Deleted documents/\(book.id.relativePath); Undo for 6 s"])
  }

  @Test func aFailedHoldLeavesNothingPending() async {
    remover.failHold(with: .changedSinceListed)

    await #expect(throws: KindleRemovalError.changedSinceListed) {
      try await removals.delete(book, listedWith: [book], on: .fixture())
    }
    #expect(await removals.pending == nil)
    #expect(log.entries().isEmpty)
  }

  @Test func undoPutsItBackAndLogsIt() async throws {
    let held = try await removals.delete(book, listedWith: [book], on: .fixture())

    try await removals.undo(held)

    #expect(remover.restored == [held.id])
    #expect(await removals.pending == nil)
    #expect(log.messages(in: .usb).last == "Put back documents/\(book.id.relativePath)")
  }

  @Test func aFailedUndoKeepsItPending() async throws {
    let held = try await removals.delete(book, listedWith: [book], on: .fixture())
    remover.failRestore(with: .occupied("documents/x.pdf"))

    await #expect(throws: KindleRemovalError.occupied("documents/x.pdf")) {
      try await removals.undo(held)
    }
    #expect(await removals.pending == held)
    #expect(log.messages(in: .usb).count == 1)
  }

  @Test func finalizeRemovesItForGoodAndNamesTheParts() async throws {
    remover.parts = [.book, .sidecar, .cover]
    let held = try await removals.delete(book, listedWith: [book], on: .fixture())

    await removals.finalize(held)

    #expect(remover.finalized == [held.id])
    #expect(await removals.pending == nil)
    #expect(
      log.messages(in: .usb).last
        == "Removed documents/\(book.id.relativePath) for good (book, sidecar, cover)")
  }

  @Test func aSecondDeleteMakesTheFirstFinal() async throws {
    let first = try await removals.delete(book, listedWith: [book, other], on: .fixture())
    let second = try await removals.delete(other, listedWith: [book, other], on: .fixture())

    #expect(remover.events == [.held(book), .finalized(first.id), .held(other)])
    #expect(await removals.pending == second)
  }

  @Test func overlappingDeletesRunOneAtATime() async throws {
    let gate = Signal()
    remover.gate = gate
    let first = Task {
      try? await removals.delete(book, listedWith: [book, other], on: .fixture())
    }
    #expect(await eventually { remover.events == [.held(book)] })

    let second = Task {
      try? await removals.delete(other, listedWith: [book, other], on: .fixture())
    }
    await letOtherTasksRun()
    #expect(remover.events == [.held(book)])
    await gate.fire()

    let firstHeld = try #require(await first.value)
    let secondHeld = try #require(await second.value)
    #expect(remover.events == [.held(book), .finalized(firstHeld.id), .held(other)])
    #expect(await removals.pending == secondHeld)
  }

  @Test func aDeleteWaitsForTheFinalizeInFlight() async throws {
    let held = try await removals.delete(book, listedWith: [book, other], on: .fixture())
    let gate = Signal()
    remover.gate = gate
    let timer = Task { await removals.finalize(held) }
    #expect(await eventually { remover.finalized == [held.id] })

    let second = Task {
      try? await removals.delete(other, listedWith: [book, other], on: .fixture())
    }
    await letOtherTasksRun()
    #expect(remover.holds == [book])
    await gate.fire()

    await timer.value
    let secondHeld = try #require(await second.value)
    #expect(remover.events == [.held(book), .finalized(held.id), .held(other)])
    #expect(await removals.pending == secondHeld)
  }

  @Test func aFinalizeDuringAnUndoDoesNothing() async throws {
    let held = try await removals.delete(book, listedWith: [book], on: .fixture())
    let gate = Signal()
    remover.gate = gate
    let undo = Task { try? await removals.undo(held) }
    #expect(await eventually { remover.restored == [held.id] })

    let timer = Task { await removals.finalize(held) }
    await letOtherTasksRun()
    await gate.fire()

    #expect(await undo.value != nil)
    await timer.value
    #expect(remover.events == [.held(book), .restored(held.id)])
    #expect(await removals.pending == nil)
  }

  @Test func aFailedFinalizeIsLoggedAndDropped() async throws {
    remover.failFinalize(with: .deviceDisconnected)
    _ = try await removals.delete(book, listedWith: [book], on: .fixture())

    await removals.finalizePending()

    #expect(await removals.pending == nil)
    #expect(
      log.summary.last
        == "warning USB Couldn't remove documents/\(book.id.relativePath): the Kindle was unplugged"
    )
  }

  @Test func finalizingAnOldHoldTwiceDoesNothing() async throws {
    let held = try await removals.delete(book, listedWith: [book], on: .fixture())

    await removals.finalize(held)
    await removals.finalize(held)

    #expect(remover.finalized == [held.id])
  }

  @Test func aHoldThatIsNoLongerPendingChangesNothing() async throws {
    let old = try await removals.delete(book, listedWith: [book, other], on: .fixture())
    let current = try await removals.delete(other, listedWith: [book, other], on: .fixture())

    try await removals.undo(old)
    await removals.finalize(old)

    #expect(remover.restored.isEmpty)
    #expect(remover.finalized == [old.id])
    #expect(await removals.pending == current)
  }

  @Test func finalizePendingRemovesTheHeldBookOnce() async throws {
    let held = try await removals.delete(book, listedWith: [book], on: .fixture())

    await removals.finalizePending()
    await removals.finalizePending()

    #expect(remover.finalized == [held.id])
    #expect(await removals.pending == nil)
  }

  @Test(arguments: [
    (2, "Cleared 2 held items left from before"), (1, "Cleared 1 held item left from before"),
  ])
  func clearingLeftoversLogsHowManyWereCleared(count: Int, line: String) async {
    let volume = KindleVolume.fixture()
    remover.leftovers = count

    await removals.clearLeftovers(on: volume)

    #expect(remover.clearedVolumes == [volume])
    #expect(log.summary == ["info USB \(line)"])
  }

  @Test func clearingNothingLeavesTheLogAlone() async {
    remover.leftovers = 0

    await removals.clearLeftovers(on: .fixture())

    #expect(log.messages(in: .usb).isEmpty)
  }

  @Test func removingForGoodHoldsThenFinalizesAtOnce() async throws {
    try await remover.removeForGood(book, listedWith: [book], on: .fixture())

    #expect(remover.holds == [book])
    #expect(remover.finalized.count == 1)
    #expect(remover.events.count == 2)
  }

  @Test func removingForGoodStopsWhenTheHoldFails() async {
    remover.failHold(with: .deviceDisconnected)

    await #expect(throws: KindleRemovalError.deviceDisconnected) {
      try await remover.removeForGood(book, listedWith: [book], on: .fixture())
    }
    #expect(remover.finalized.isEmpty)
  }

  @Test(
    arguments: [
      (KindleRemovalError.changedSinceListed, "it changed on the Kindle since Sendle read it"),
      (.deviceDisconnected, "the Kindle was unplugged"),
      (.occupied("documents/x.pdf"), "documents/x.pdf is in its place"),
      (.failed("the disk is read-only"), "the disk is read-only"),
    ])
  func removalErrorsReadAsADetail(error: KindleRemovalError, detail: String) {
    #expect(error.detail == detail)
  }

  /// Lets tasks started a moment ago reach the actor, so a call that should wait is waiting.
  private func letOtherTasksRun() async {
    for _ in 0..<50 { await Task.yield() }
  }
}
