import Foundation
import SendleDomain
import SendleTestSupport
import SendleUI
import Testing
import os

@MainActor @Suite(.timeLimit(.minutes(1)))
struct PanelKindleDeleteTests {
  let harness = PanelHarness()
  let remover = FakeKindleBookRemover()

  /// Sendle's own PDF of Moby-Dick, the library's book "a".
  let mobyDick = KindleBook.fixture(
    path: "Moby-Dick - Herman Melville.pdf", source: .sendle, asin: "SNMOBYDICK",
    asinFollowsFileName: true)
  let typee = KindleBook.fixture(
    path: "Typee - Nobody.azw3", title: "Typee", authors: ["Nobody"])

  /// The Kindle side, with the sheet of the first book of `listing` open.
  private func panelWithSheet(
    on listing: [KindleBook]? = nil, ejector: FakeKindleEjector? = nil,
    removalSleep: @escaping @Sendable (Duration) async -> Void = { _ in
      try? await Task.sleep(for: .seconds(60))
    },
    channel: FakeDeliveryChannel = FakeDeliveryChannel()
  ) async -> (panel: PanelModel, kindle: FakeKindleLibrary) {
    let listing = listing ?? [mobyDick]
    let (panel, kindle, _) = await harness.pluggedInPanel(
      listing: listing, ejector: ejector, remover: remover, removalSleep: removalSleep,
      channel: channel)
    panel.showSide(.kindle)
    panel.openKindleDetails(listing[0].id)
    #expect(panel.kindleDetails?.item.book.id == listing[0].id)
    return (panel, kindle)
  }

  /// Deletes the open sheet's book; returns what Undo would put back.
  private func delete(on panel: PanelModel) async -> HeldBook? {
    panel.askToDeleteKindleBook()
    await panel.deleteKindleBook()
    return panel.removal?.toast
  }

  @Test func deleteAsksFirstInTheSheet() async {
    let (panel, _) = await panelWithSheet()

    panel.askToDeleteKindleBook()
    #expect(panel.removal?.stage == .confirming)

    #expect(panel.handle(KeyInput(.escape)))
    #expect(panel.removal?.stage == .idle)
    #expect(panel.kindleDetails != nil)
    #expect(remover.holds == [])
  }

  @Test func returnDeletesAndClosesTheSheet() async {
    let (panel, kindle) = await panelWithSheet()
    let reads = kindle.listings
    panel.askToDeleteKindleBook()

    #expect(panel.handle(KeyInput(.returnKey)))

    #expect(await eventually { panel.removal?.toast != nil && kindle.listings > reads })
    #expect(remover.holds == [mobyDick])
    #expect(remover.listings == [[mobyDick]])
    #expect(panel.kindleDetails == nil)
    #expect(panel.removal?.toast?.book == mobyDick)
    #expect(panel.removal?.stage == .idle)
    #expect(panel.notice == nil)
  }

  @Test func aHeldReturnDeletesNothing() async {
    let (panel, _) = await panelWithSheet()
    panel.askToDeleteKindleBook()

    #expect(panel.handle(KeyInput(.returnKey, isRepeat: true)))
    await Task.yield()

    #expect(remover.holds == [])
    #expect(panel.removal?.stage == .confirming)
    #expect(panel.kindleDetails != nil)
  }

  @Test func returnWhileDeletingKeepsTheSheet() async {
    let (panel, _) = await panelWithSheet()
    let gate = Signal()
    remover.gate = gate
    panel.askToDeleteKindleBook()
    #expect(panel.handle(KeyInput(.returnKey)))
    #expect(await eventually { panel.removal?.stage == .deleting })

    #expect(panel.handle(KeyInput(.returnKey, isRepeat: true)))
    #expect(panel.handle(KeyInput(.returnKey)))

    #expect(panel.kindleDetails != nil)
    await gate.fire()
    #expect(await eventually { panel.removal?.toast != nil })
    #expect(remover.holds == [mobyDick])
  }

  @Test func aHeldReturnAfterAFailedDeleteKeepsItsNote() async {
    let (panel, _) = await panelWithSheet()
    remover.failHold(with: .failed("busy"))
    panel.askToDeleteKindleBook()
    await panel.deleteKindleBook()

    #expect(panel.handle(KeyInput(.returnKey, isRepeat: true)))

    #expect(panel.kindleDetails != nil)
    #expect(panel.removal?.failure == "Couldn't delete \"Moby-Dick\": busy.")
  }

  @Test func returnWithoutTheQuestionStillCloses() async {
    let (panel, _) = await panelWithSheet()

    #expect(panel.handle(KeyInput(.returnKey)))

    #expect(panel.kindleDetails == nil)
    #expect(remover.holds == [])
  }

  @Test func undoPutsItBack() async throws {
    let (panel, kindle) = await panelWithSheet()
    #expect(!panel.handle(KeyInput(.character("z"), command: true)))
    let held = try #require(await delete(on: panel))
    let reads = kindle.listings

    #expect(panel.handle(KeyInput(.character("z"), command: true)))

    #expect(await eventually { remover.restored == [held.id] && panel.removal?.toast == nil })
    #expect(await eventually { kindle.listings > reads })
    #expect(remover.finalized == [])
  }

  @Test func theToastEndingMakesItFinal() async throws {
    let ending = Signal()
    let asked = OSAllocatedUnfairLock<[Duration]>(initialState: [])
    let (panel, kindle) = await panelWithSheet(removalSleep: { duration in
      asked.withLock { $0.append(duration) }
      await ending.wait()
    })
    let held = try #require(await delete(on: panel))
    let reads = kindle.listings

    await ending.fire()

    #expect(await eventually { remover.finalized == [held.id] && panel.removal?.toast == nil })
    #expect(await eventually { kindle.listings > reads })
    #expect(asked.withLock { $0 } == [KindleRemovals.undoWindow])
  }

  @Test func theToastGoesBeforeItsDeleteIsFinal() async throws {
    let ending = Signal()
    let (panel, _) = await panelWithSheet(removalSleep: { _ in await ending.wait() })
    let held = try #require(await delete(on: panel))
    let gate = Signal()
    remover.gate = gate

    await ending.fire()

    #expect(await eventually { remover.finalized == [held.id] })
    #expect(panel.removal?.toast == nil)
    #expect(panel.hasPendingKindleDelete)
    #expect(!panel.handle(KeyInput(.character("z"), command: true)))
    await gate.fire()
    #expect(await eventually { !panel.hasPendingKindleDelete })
    #expect(remover.restored == [])
  }

  @Test func theToastSaysWhenItsTimeRunsOut() async throws {
    let (panel, _) = await panelWithSheet()
    let window = KindleRemovals.undoWindow / .seconds(1)
    let before = Date()
    _ = try #require(await delete(on: panel))
    let after = Date()

    let ends = try #require(panel.removal?.toastEnds)

    #expect(ends >= before.addingTimeInterval(window))
    #expect(ends <= after.addingTimeInterval(window))
    await panel.undoKindleDelete()
    #expect(panel.removal?.toastEnds == nil)
  }

  @Test func theToastsBookOpensNoSheet() async throws {
    let (panel, _) = await panelWithSheet()
    let held = try #require(await delete(on: panel))

    panel.openKindleDetails(held.book.id)

    #expect(panel.kindleDetails == nil)
  }

  @Test func commandZUndoesOnlyWhereTheToastShows() async throws {
    let (panel, _) = await panelWithSheet()
    let held = try #require(await delete(on: panel))
    let undo = KeyInput(.character("z"), command: true)
    #expect(panel.undoToast == held)

    panel.showSide(.library)
    #expect(panel.undoToast == nil)
    #expect(!panel.handle(undo))
    panel.showSide(.kindle)
    await panel.openSettings()
    #expect(panel.undoToast == nil)
    #expect(!panel.handle(undo))
    panel.closeSettings()
    panel.openLogs()
    #expect(!panel.handle(undo))
    panel.closeLogs()
    await Task.yield()
    #expect(remover.restored == [])

    #expect(panel.handle(undo))
    #expect(await eventually { remover.restored == [held.id] })
  }

  @Test func aSecondDeleteReplacesTheToast() async throws {
    let (panel, _) = await panelWithSheet(on: [mobyDick, typee])
    let first = try #require(await delete(on: panel))
    panel.openKindleDetails(typee.id)

    let second = try #require(await delete(on: panel))

    #expect(remover.finalized == [first.id])
    #expect(second.book == typee)
    #expect(panel.kindleDetails == nil)
  }

  @Test func aSecondDeleteDropsTheToastBeforeItsDeleteIsFinal() async throws {
    let (panel, _) = await panelWithSheet(on: [mobyDick, typee])
    let first = try #require(await delete(on: panel))
    panel.openKindleDetails(typee.id)
    let gate = Signal()
    remover.gate = gate
    panel.askToDeleteKindleBook()

    let deleting = Task { await panel.deleteKindleBook() }

    #expect(await eventually { remover.finalized == [first.id] })
    #expect(panel.removal?.toast == nil)
    #expect(panel.hasPendingKindleDelete)
    await gate.fire()
    await deleting.value
    #expect(panel.removal?.toast?.book == typee)
  }

  @Test func ejectingMakesItFinalFirst() async throws {
    let gate = Signal()
    let ejector = FakeKindleEjector(gate: gate)
    let (panel, _) = await panelWithSheet(ejector: ejector)
    let held = try #require(await delete(on: panel))

    let ejecting = Task { await panel.eject(.fixture()) }

    #expect(await eventually { ejector.ejected == [.fixture()] })
    #expect(remover.finalized == [held.id])
    #expect(panel.removal?.toast == nil)
    await gate.fire()
    await ejecting.value
  }

  @Test func ejectingDropsTheToastBeforeItsDeleteIsFinal() async throws {
    let (panel, _) = await panelWithSheet()
    let held = try #require(await delete(on: panel))
    let gate = Signal()
    remover.gate = gate

    let ejecting = Task { await panel.eject(.fixture()) }

    #expect(await eventually { remover.finalized == [held.id] })
    #expect(panel.removal?.toast == nil)
    #expect(panel.hasPendingKindleDelete)
    #expect(!panel.handle(KeyInput(.character("z"), command: true)))
    await gate.fire()
    await ejecting.value
    #expect(!panel.hasPendingKindleDelete)
    #expect(remover.restored == [])
  }

  @Test func sendingToTheKindleMakesItFinalFirst() async throws {
    let (panel, kindle) = await panelWithSheet()
    let held = try #require(await delete(on: panel))
    let reads = kindle.listings
    let gate = Signal()
    remover.gate = gate

    let sending = Task { await panel.quickSend(BookID(rawValue: "b")) }

    #expect(await eventually { remover.finalized == [held.id] })
    #expect(kindle.listings == reads)
    await gate.fire()
    await sending.value
    #expect(kindle.listings > reads)
    #expect(panel.removal?.toast == nil)
  }

  @Test func aChangedBookSaysSoAndRereads() async {
    let (panel, kindle) = await panelWithSheet()
    remover.failHold(with: .changedSinceListed)
    let reads = kindle.listings

    panel.askToDeleteKindleBook()
    await panel.deleteKindleBook()

    #expect(panel.kindleDetails?.item.book.id == mobyDick.id)
    #expect(panel.removal?.stage == .idle)
    #expect(
      panel.removal?.failure
        == "This book changed on the Kindle since Sendle read it. Sendle has read the Kindle "
        + "again; try again if you still want to delete it.")
    #expect(kindle.listings > reads)
    #expect(panel.removal?.toast == nil)
  }

  @Test func tryingAgainDeletesTheBookAsTheKindleWasReadAgain() async {
    let (panel, kindle) = await panelWithSheet()
    let changed = KindleBook.fixture(
      path: mobyDick.id.relativePath, source: .sendle, asin: "SNMOBYDICK",
      asinFollowsFileName: true, byteCount: 2_000_000)
    kindle.result = .success(.fixture([changed]))
    remover.failHold(with: .changedSinceListed)
    _ = await delete(on: panel)

    remover.failHold(with: nil)
    _ = await delete(on: panel)

    #expect(remover.holds.last == changed)
    #expect(remover.listings.last == [changed])
  }

  @Test func anotherFailureIsShownInTheSheet() async {
    let (panel, kindle) = await panelWithSheet()
    remover.failHold(with: .failed("busy"))
    let reads = kindle.listings

    panel.askToDeleteKindleBook()
    await panel.deleteKindleBook()

    #expect(panel.removal?.failure == "Couldn't delete \"Moby-Dick\": busy.")
    #expect(kindle.listings == reads)
    #expect(panel.kindleDetails != nil)
    #expect(panel.removal?.stage == .idle)
    panel.closeKindleDetails()
    #expect(panel.removal?.failure == nil)
  }

  @Test func aFailureAfterAToastRereadsTheKindle() async throws {
    let (panel, kindle) = await panelWithSheet(on: [mobyDick, typee])
    let first = try #require(await delete(on: panel))
    panel.openKindleDetails(typee.id)
    remover.failHold(with: .failed("busy"))
    let reads = kindle.listings

    panel.askToDeleteKindleBook()
    await panel.deleteKindleBook()

    #expect(remover.finalized == [first.id])
    #expect(kindle.listings > reads)
    #expect(panel.kindleDetails?.item.book.id == typee.id)
    #expect(panel.removal?.failure == "Couldn't delete \"Typee\": busy.")
    #expect(panel.removal?.toast == nil)
  }

  @Test func deleteWaitsWhileTheKindleIsCopiedTo() async {
    let channel = FakeDeliveryChannel(.hangUntilCancelled)
    let (panel, _) = await panelWithSheet(channel: channel)
    #expect(panel.canDeleteKindleBook)

    await panel.quickSend(BookID(rawValue: "b"))
    await channel.waitUntilDeliveryStarts()

    #expect(!panel.canDeleteKindleBook)
    panel.askToDeleteKindleBook()
    #expect(panel.removal?.stage == .idle)
    panel.queue.cancel()
    await panel.queue.waitUntilFinished()
    #expect(panel.canDeleteKindleBook)
  }

  @Test func deleteWaitsWhileEjecting() async {
    let gate = Signal()
    let (panel, _) = await panelWithSheet(ejector: FakeKindleEjector(gate: gate))
    #expect(panel.canDeleteKindleBook)

    let ejecting = Task { await panel.eject(.fixture()) }
    #expect(await eventually { panel.ejecting != nil })

    #expect(!panel.canDeleteKindleBook)
    panel.askToDeleteKindleBook()
    #expect(panel.removal?.stage == .idle)
    await gate.fire()
    await ejecting.value
  }

  @Test func deleteWaitsForAKindleThatCanBeRead() async {
    let (panel, kindle) = await panelWithSheet()
    kindle.result = .failure(.unreadable("I/O error"))

    await panel.kindle.refresh()

    #expect(panel.kindle.listing == nil)
    #expect(panel.kindleDetails != nil)
    #expect(!panel.canDeleteKindleBook)
    panel.askToDeleteKindleBook()
    #expect(panel.removal?.stage == .idle)
  }

  @Test func deleteWaitsWhileTheKindleIsChecked() async {
    let (panel, kindle) = await panelWithSheet()
    let gate = Signal()
    kindle.gate = gate
    let sending = Task { await panel.quickSend(BookID(rawValue: "b")) }
    #expect(await eventually { panel.checkingKindle != nil })

    #expect(!panel.canDeleteKindleBook)
    await gate.fire()
    await sending.value
  }

  @Test func unpluggingDuringUndoDropsTheToast() async throws {
    let (panel, _) = await panelWithSheet()
    let held = try #require(await delete(on: panel))

    harness.monitor.update([])

    #expect(await eventually { panel.removal?.toast == nil })
    #expect(remover.finalized == [held.id])
    #expect(panel.notice == nil)
  }

  @Test func aFailedUndoSaysSoAndKeepsTheToast() async throws {
    let (panel, _) = await panelWithSheet()
    let held = try #require(await delete(on: panel))
    remover.failRestore(with: .occupied("documents/x.pdf"))

    await panel.undoKindleDelete()

    #expect(panel.notice?.title == "Couldn't put \"Moby-Dick\" back")
    #expect(panel.notice?.message == "Another file is at documents/x.pdf now.")
    #expect(panel.removal?.toast == held)
  }

  @Test func pluggingInClearsLeftovers() async {
    _ = await harness.pluggedInPanel(listing: [mobyDick], remover: remover)

    #expect(await eventually { remover.clearedVolumes == [.fixture()] })
  }

  @Test func quittingMakesItFinal() async throws {
    let (panel, _) = await panelWithSheet()
    let held = try #require(await delete(on: panel))
    #expect(panel.hasPendingKindleDelete)

    await panel.prepareToQuit()

    #expect(remover.finalized == [held.id])
    #expect(!panel.hasPendingKindleDelete)
  }

  @Test func withoutARemoverThereIsNoDelete() async {
    let (panel, _, _) = await harness.pluggedInPanel(listing: [mobyDick])
    panel.showSide(.kindle)
    panel.openKindleDetails(mobyDick.id)

    #expect(panel.kindleDetails != nil)
    #expect(!panel.canDeleteKindleBook)
    #expect(!panel.hasPendingKindleDelete)
  }
}
