import Foundation
import SendleDomain
import SendleTestSupport
import SendleUI
import Testing
import os

@MainActor @Suite(.timeLimit(.minutes(1)))
struct PanelHideTests {
  let harness = PanelHarness()
  let undo = KeyInput(.character("z"), command: true)
  let a = BookID(rawValue: "a")
  let b = BookID(rawValue: "b")
  let c = BookID(rawValue: "c")
  let d = BookID(rawValue: "d")

  /// Four books that can go by email, read and on screen, with `store` keeping the hidden ones.
  private func panel(
    store: InMemoryHiddenBooksStore = InMemoryHiddenBooksStore(),
    removalSleep: @escaping @Sendable (Duration) async -> Void = { _ in
      try? await Task.sleep(for: .seconds(60))
    }
  ) async -> PanelModel {
    harness.library.result = .success([
      .fixture(id: "a", title: "The Art of War", author: "Sun Tzu"),
      .fixture(id: "b", title: "Dracula", author: "Bram Stoker"),
      .fixture(id: "c", title: "Emma", author: "Jane Austen"),
      .fixture(id: "d", title: "Walden", author: "Henry David Thoreau"),
    ])
    let (panel, _) = harness.makePanel(hiddenBooks: store, removalSleep: removalSleep)
    await panel.launch()
    await panel.panelDidOpen()
    return panel
  }

  private func select(_ ids: [BookID], in panel: PanelModel) {
    for (index, id) in ids.enumerated() {
      panel.click(id, index == 0 ? .plain : .toggle)
    }
  }

  @Test func hidingABookHidesItAndShowsAnUndoToast() async throws {
    let panel = await panel()

    await panel.hideFromSendle(a)

    #expect(panel.library.hidden == [a])
    #expect(!panel.library.items.contains { $0.id == a })
    let toast = try #require(panel.hideToast)
    #expect(toast.ids == [a])
    #expect(toast.title == "Hid \"The Art of War\" from Sendle")
    #expect(panel.shownHideToast == toast)
    #expect(panel.notice == nil)
  }

  @Test func hidingFromASelectionHidesTheSelection() async {
    let panel = await panel()
    select([a, b, c], in: panel)

    await panel.hideFromSendle(b)

    #expect(panel.library.hidden == [a, b, c])
    #expect(panel.library.items.map(\.id) == [d])
    #expect(panel.library.selection.isEmpty)
    #expect(panel.hideToast?.ids == [a, b, c])
    #expect(panel.hideToast?.title == "Hid 3 books from Sendle")
  }

  @Test func hidingAnotherBookLeavesTheSelection() async {
    let panel = await panel()
    select([a, b], in: panel)

    await panel.hideFromSendle(c)

    #expect(panel.library.hidden == [c])
    #expect(panel.library.selection.ids == [a, b])
    #expect(panel.hideToast?.title == "Hid \"Emma\" from Sendle")
  }

  @Test func hidingTheOnlySelectedBookHidesJustIt() async {
    let panel = await panel()
    select([a], in: panel)

    await panel.hideFromSendle(a)

    #expect(panel.library.hidden == [a])
    #expect(panel.hideToast?.title == "Hid \"The Art of War\" from Sendle")
  }

  @Test func undoShowsThemAgain() async {
    let panel = await panel()
    select([a, b], in: panel)
    await panel.hideFromSendle(a)

    await panel.undoHide()

    #expect(panel.library.hidden.isEmpty)
    #expect(panel.library.items.count == 4)
    #expect(panel.hideToast == nil)
    #expect(panel.hideToastEnds == nil)

    await panel.hideFromSendle(c)
    #expect(panel.handle(undo))
    #expect(await eventually { panel.library.hidden.isEmpty && panel.hideToast == nil })
  }

  @Test func aFailedHideSaysWhyAndChangesNothing() async {
    let panel = await panel(
      store: InMemoryHiddenBooksStore(failure: .writeFailed("the disk is full")))

    await panel.hideFromSendle(a)

    #expect(panel.library.hidden.isEmpty)
    #expect(panel.library.items.count == 4)
    #expect(panel.hideToast == nil)
    #expect(panel.notice?.title == "Couldn't hide the book")
    #expect(panel.notice?.message == "The disk is full.")
  }

  @Test func aFailedShowSaysWhyAndChangesNothing() async {
    let panel = await panel(
      store: InMemoryHiddenBooksStore([a, b], failure: .writeFailed("the disk is full")))
    panel.library.filter = .hidden
    select([a, b], in: panel)

    await panel.showInSendle(a)

    #expect(panel.library.hidden == [a, b])
    #expect(panel.notice?.title == "Couldn't show the books in Sendle")
    #expect(panel.notice?.message == "The disk is full.")
  }

  @Test func aFailedUndoSaysWhyAndKeepsTheToast() async throws {
    let store = InMemoryHiddenBooksStore()
    let panel = await panel(store: store)
    await panel.hideFromSendle(a)
    let toast = try #require(panel.hideToast)
    await store.fail(with: .writeFailed("the disk is full"))

    await panel.undoHide()

    #expect(panel.hideToast == toast)
    #expect(panel.library.hidden == [a])
    #expect(panel.notice?.title == "Couldn't show the book in Sendle")
  }

  @Test func theToastGoesWhenItsTimeRunsOut() async throws {
    let ending = Signal()
    let asked = OSAllocatedUnfairLock<[Duration]>(initialState: [])
    let panel = await panel(removalSleep: { duration in
      asked.withLock { $0.append(duration) }
      await ending.wait()
    })
    let window = KindleRemovals.undoWindow / .seconds(1)
    let before = Date()
    await panel.hideFromSendle(a)
    let after = Date()
    let ends = try #require(panel.hideToastEnds)
    #expect(ends >= before.addingTimeInterval(window))
    #expect(ends <= after.addingTimeInterval(window))

    await ending.fire()

    #expect(await eventually { panel.hideToast == nil })
    #expect(panel.hideToastEnds == nil)
    #expect(asked.withLock { $0 } == [KindleRemovals.undoWindow])
    #expect(panel.library.hidden == [a])
    #expect(!panel.handle(undo))
  }

  @Test func eachToastKeepsItsOwnTime() async {
    let endings = OSAllocatedUnfairLock<[Signal]>(initialState: [])
    let panel = await panel(removalSleep: { _ in
      let ending = Signal()
      endings.withLock { $0.append(ending) }
      await ending.wait()
    })
    func end(_ index: Int) async {
      _ = await eventually { endings.withLock { $0.count } > index }
      await endings.withLock { $0[index] }.fire()
      try? await Task.sleep(for: .milliseconds(50))
    }
    await panel.hideFromSendle(a)
    await panel.undoHide()
    await panel.hideFromSendle(a)

    await end(0)
    #expect(panel.hideToast?.ids == [a])
    await panel.hideFromSendle(b)
    await end(1)
    #expect(panel.hideToast?.ids == [b])
    await end(2)
    #expect(panel.hideToast == nil)
  }

  @Test func aSecondHideReplacesTheToast() async {
    let panel = await panel()
    await panel.hideFromSendle(a)

    await panel.hideFromSendle(b)
    await panel.undoHide()

    #expect(panel.library.hidden == [a])
    #expect(panel.hideToast == nil)
  }

  @Test func showInSendleShowsTheBooksFollowingTheSelection() async {
    let panel = await panel(store: InMemoryHiddenBooksStore([a, b, c]))
    panel.library.filter = .hidden
    select([a, b], in: panel)

    await panel.showInSendle(c)
    #expect(panel.library.hidden == [a, b])

    await panel.showInSendle(a)
    #expect(panel.library.hidden.isEmpty)
    #expect(panel.library.filter == .all)
    #expect(panel.hideToast == nil)
  }

  @Test func showingTheBooksTheToastHidDropsTheToastAndItsTime() async {
    let endings = OSAllocatedUnfairLock<[Signal]>(initialState: [])
    let panel = await panel(removalSleep: { _ in
      let ending = Signal()
      endings.withLock { $0.append(ending) }
      await ending.wait()
    })
    select([a, b], in: panel)
    await panel.hideFromSendle(a)
    panel.library.filter = .hidden

    await panel.showInSendle(b)

    #expect(panel.library.hidden == [a])
    #expect(panel.hideToast == nil)
    #expect(panel.hideToastEnds == nil)
    #expect(!panel.handle(undo))

    await panel.hideFromSendle(c)
    _ = await eventually { endings.withLock { $0.count } > 0 }
    await endings.withLock { $0[0] }.fire()
    try? await Task.sleep(for: .milliseconds(50))
    #expect(panel.hideToast?.ids == [c])
  }

  @Test func showingOtherBooksKeepsTheToast() async {
    let panel = await panel(store: InMemoryHiddenBooksStore([c]))
    await panel.hideFromSendle(a)
    panel.library.filter = .hidden

    await panel.showInSendle(c)

    #expect(panel.library.hidden == [a])
    #expect(panel.hideToast?.ids == [a])
  }

  @Test func aFailedShowKeepsTheToast() async {
    let store = InMemoryHiddenBooksStore()
    let panel = await panel(store: store)
    await panel.hideFromSendle(a)
    panel.library.filter = .hidden
    await store.fail(with: .writeFailed("the disk is full"))

    await panel.showInSendle(a)

    #expect(panel.hideToast?.ids == [a])
  }

  @Test func toggleHiddenHidesInTheOtherScopesAndShowsInHidden() async {
    let panel = await panel(store: InMemoryHiddenBooksStore([d]))
    panel.library.filter = .all

    await panel.toggleHidden(a)
    #expect(panel.library.hidden == [a, d])
    #expect(panel.hideToast?.ids == [a])

    panel.library.filter = .hidden
    await panel.toggleHidden(d)
    #expect(panel.library.hidden == [a])
    #expect(panel.hideToast?.ids == [a])
    #expect(panel.hideMenuTitle(for: a) == "Show in Sendle")
  }

  @Test func showInBooksOpensBooksAtTheBook() async throws {
    let panel = await panel()

    panel.showInBooks(a)
    panel.showInBooks(BookID(rawValue: "id with/slash"))

    #expect(
      harness.system.opened == [
        try #require(URL(string: "ibooks://assetid/a")),
        try #require(URL(string: "ibooks://assetid/id%20with%2Fslash")),
      ])
    #expect(panel.library.hidden.isEmpty)
  }

  @Test func theMenuTitleFollowsTheScopeAndTheSelection() async {
    let panel = await panel()
    #expect(panel.hideMenuTitle(for: a) == "Hide from Sendle")
    select([a], in: panel)
    #expect(panel.hideMenuTitle(for: a) == "Hide from Sendle")
    select([a, b, c], in: panel)
    #expect(panel.hideMenuTitle(for: a) == "Hide 3 Books from Sendle")
    #expect(panel.hideMenuTitle(for: d) == "Hide from Sendle")

    await panel.hideFromSendle(d)
    await panel.hideFromSendle(a)
    panel.library.filter = .hidden
    #expect(panel.hideMenuTitle(for: c) == "Show in Sendle")
    select([c, d], in: panel)
    #expect(panel.hideMenuTitle(for: c) == "Show 2 Books in Sendle")
    #expect(panel.hideMenuTitle(for: a) == "Show in Sendle")
  }

  @Test func commandZUndoesTheHideOnlyOnTheLibrarySide() async {
    let (panel, _, _) = await harness.pluggedInPanel(listing: [])
    await panel.hideFromSendle(a)
    #expect(panel.shownHideToast != nil)

    panel.showSide(.kindle)
    #expect(panel.shownHideToast == nil)
    #expect(!panel.handle(undo))
    panel.showSide(.library)
    await panel.openSettings()
    #expect(panel.shownHideToast == nil)
    #expect(!panel.handle(undo))
    panel.closeSettings()
    panel.openLogs()
    #expect(!panel.handle(undo))
    panel.closeLogs()
    #expect(!panel.handle(KeyInput(.character("z"), command: true, isRepeat: true)))
    await Task.yield()
    #expect(panel.library.hidden == [a])

    #expect(panel.handle(undo))
    #expect(await eventually { panel.library.hidden.isEmpty })
  }
}
