import Foundation
import SendleDomain
import SendleTestSupport
import SendleUI
import Testing
import os

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct LibraryViewModelTests {
  let library = FakeBooksLibrary(.success([.fixture(id: "a"), .fixture(id: "b")]))
  let monitor = FakeDestinationMonitor()
  let history = InMemorySendHistoryStore()
  let kindle = KindleVolume.fixture()

  func makeModel(
    _ saved: AppSettings = AppSettings(email: .fixture),
    converter: FakeFormatConverter = FakeFormatConverter(isAvailable: false)
  ) -> (LibraryViewModel, InMemorySettingsStore) {
    let settings = InMemorySettingsStore(saved)
    let model = LibraryViewModel(
      loadLibrary: LoadLibrary(library: library, inspector: StubProtectionInspector()),
      observeDestinations: ObserveDestinations(monitor: monitor, settings: settings),
      settings: settings, history: history, converter: converter,
      now: { Date(timeIntervalSince1970: 1_800_000_000) })
    return (model, settings)
  }

  func books(_ ids: [String], format: BookFormat = .epub) -> [Book] {
    ids.map { Book.fixture(id: $0, format: format) }
  }

  // MARK: Loading

  @Test func loadsTheLibraryWhenThePanelOpens() async throws {
    try await history.append(
      SendRecord(bookID: BookID(rawValue: "a"), destination: .email, date: .now, outcome: .sent))
    let (model, _) = makeModel()

    await model.appear()

    #expect(model.state == .loaded)
    #expect(model.items.map(\.id.rawValue) == ["a", "b"])
    #expect(model.items.first?.tone == .sent)
    #expect(model.summary == "2 books · 2 sendable")
  }

  @Test func countsOnlyBooksThatCanBeSent() async {
    library.result = .success([.fixture(id: "a"), .fixture(id: "b", availability: .protected)])
    let (model, _) = makeModel()
    await model.appear()
    #expect(model.summary == "2 books · 1 sendable")

    library.result = .success([.fixture(id: "a")])
    await model.reload()
    #expect(model.summary == "1 book · 1 sendable")
  }

  @Test func explainsWhyTheLibraryCannotBeRead() async {
    library.result = .failure(.accessDenied)
    library.canWatch = false
    let (model, _) = makeModel()

    await model.appear()

    #expect(model.state == .failed(ProblemPresenter.problem(for: .accessDenied)))
    #expect(model.needsAccess)
    #expect(model.items.isEmpty)
  }

  @Test func keepsTheLastBooksWhenAReloadFails() async {
    let (model, _) = makeModel()
    var reported: [Problem] = []
    model.reportProblem = { reported.append($0) }
    await model.appear()

    library.result = .failure(.unreadable("disk I/O error"))
    await model.reload()

    #expect(model.state == .loaded)
    #expect(model.items.map(\.id.rawValue) == ["a", "b"])
    #expect(reported == [ProblemPresenter.problem(for: .unreadable("disk I/O error"))])
  }

  @Test func dropsTheBooksWhenAccessIsTakenAway() async {
    let (model, _) = makeModel()
    var reported: [Problem] = []
    model.reportProblem = { reported.append($0) }
    await model.appear()

    library.result = .failure(.accessDenied)
    await model.reload()

    #expect(model.state == .failed(ProblemPresenter.problem(for: .accessDenied)))
    #expect(model.items.isEmpty)
    #expect(reported.isEmpty)
  }

  @Test func runsOneReloadAtATimeSoTheLatestWins() async {
    let (model, _) = makeModel()
    let gate = Signal()
    library.gate = gate
    let first = Task { await model.reload() }
    #expect(await eventually { library.loads == 1 })

    library.result = .success(books(["new"]))
    library.gate = nil
    let second = Task { await model.reload() }

    await gate.fire()
    await first.value
    await second.value

    #expect(model.items.map(\.id.rawValue) == ["new"])
    #expect(library.loads == 2)
    #expect(library.maxConcurrentLoads == 1)
  }

  @Test func readsNewSendsWithoutReadingBooksAgain() async throws {
    let (model, _) = makeModel()
    await model.appear()
    let loads = library.loads

    try await history.append(
      SendRecord(bookID: BookID(rawValue: "b"), destination: .email, date: .now, outcome: .sent))
    await model.refreshHistory()

    #expect(model.items.last?.tone == .sent)
    #expect(library.loads == loads)
  }

  @Test func aNewSendDropsTheBookFromTheSelectionUnderNotSent() async throws {
    let (model, _) = makeModel()
    await model.appear()
    model.filter = .notSent
    model.click(BookID(rawValue: "b"), .plain)
    #expect(model.selection.ids == [BookID(rawValue: "b")])

    try await history.append(
      SendRecord(bookID: BookID(rawValue: "b"), destination: .email, date: .now, outcome: .sent))
    await model.refreshHistory()

    #expect(model.selection.isEmpty)
  }

  // MARK: Watching Books

  @Test func reloadsWhenBooksChangesWhileThePanelIsOpen() async {
    let (model, _) = makeModel()
    await model.appear()

    library.result = .success(books(["a", "b", "c"]))
    library.announceChange()

    #expect(await eventually { model.items.count == 3 })
  }

  @Test func stopsWatchingBooksWhenThePanelCloses() async {
    let (model, _) = makeModel()
    await model.appear()
    #expect(library.changeSubscribers == 1)

    model.disappear()

    #expect(await eventually { library.changeSubscribers == 0 })
  }

  @Test func startsWatchingOnceAccessIsGranted() async {
    library.result = .failure(.accessDenied)
    library.canWatch = false
    let (model, _) = makeModel()
    await model.appear()

    library.result = .success(books(["a"]))
    library.canWatch = true
    await model.reload()

    #expect(model.state == .loaded)
    #expect(library.changeSubscribers == 1)
  }

  @Test func reopeningThePanelKeepsASingleWatcher() async throws {
    let (model, _) = makeModel()
    await model.appear()
    model.disappear()
    await model.appear()
    try await Task.sleep(for: .milliseconds(100))

    await model.reload()

    #expect(library.changeSubscribers == 1)
  }

  // MARK: Destinations and layout

  @Test func startsWithTheRememberedLayoutAndDestination() async {
    let (model, _) = makeModel(AppSettings(layout: .list, activeDestination: .usb))

    await model.start()

    #expect(model.layout == .list)
    #expect(model.preferredDestination == .usb)
  }

  @Test func listsDestinationsAndKeepsTheSavedOneActive() async {
    let (model, _) = makeModel()
    await model.start()
    #expect(await eventually { model.destinations == [.email(.fixture)] })

    monitor.update([kindle])

    #expect(await eventually { model.destinations == [.usb(kindle), .email(.fixture)] })
    #expect(model.activeDestination == .email(.fixture))
  }

  @Test func fallsBackToAnotherDestinationWhileTheSavedOneIsAway() async {
    let (model, _) = makeModel(AppSettings(email: .fixture, activeDestination: .usb))
    await model.start()

    #expect(await eventually { model.activeDestination == .email(.fixture) })
    #expect(model.preferredDestination == .usb)
  }

  @Test func remembersTheChosenDestinationAndLayout() async {
    let (model, settings) = makeModel()

    await model.activate(.usb)
    await model.setLayout(.shelf)

    #expect(await settings.settings.activeDestination == .usb)
    #expect(await settings.settings.layout == .shelf)
    #expect(model.layout == .shelf)
  }

  @Test func showsANewKindleEmailWithoutWaitingForAUSBChange() async throws {
    let (model, settings) = makeModel(AppSettings())
    await model.start()
    monitor.update([kindle])
    #expect(await eventually { model.destinations == [.usb(kindle)] })
    #expect(!model.hasKindleEmail)

    try await settings.update { $0.email = .fixture }
    await model.refreshSettings()

    #expect(model.destinations == [.usb(kindle), .email(.fixture)])
    #expect(model.hasKindleEmail)
  }

  @Test func anyPluggedInKindleCanBeChosen() async {
    let oasis = KindleVolume.fixture(name: "Kindle Oasis")
    let (model, settings) = makeModel()
    await model.start()
    monitor.update([kindle, oasis])
    #expect(await eventually { model.destinations.count == 3 })

    await model.activate(.usb(oasis))

    #expect(model.activeDestination == .usb(oasis))
    #expect(await settings.settings.activeDestination == .usb)
  }

  @Test func aChosenKindleThatGoesAwayGivesWayToTheOtherAndComesBackChosen() async {
    let oasis = KindleVolume.fixture(name: "Kindle Oasis")
    let (model, _) = makeModel()
    await model.start()
    monitor.update([kindle, oasis])
    #expect(await eventually { model.destinations.count == 3 })
    await model.activate(.usb(oasis))

    monitor.update([kindle])
    #expect(await eventually { model.activeDestination == .usb(kindle) })

    monitor.update([kindle, oasis])
    #expect(await eventually { model.activeDestination == .usb(oasis) })
  }

  @Test func theKindleReadStaysWhileItIsPluggedInAndAnotherArrives() async {
    let basic = KindleVolume.fixture(name: "Kindle Basic")
    let paperwhite = KindleVolume.fixture(name: "Kindle Paperwhite")
    let (model, _) = makeModel()
    await model.start()
    monitor.update([paperwhite])
    #expect(await eventually { model.kindleVolume == paperwhite })

    monitor.update([basic, paperwhite])
    #expect(await eventually { model.destinations.count == 3 })
    #expect(model.kindleVolume == paperwhite)

    monitor.update([basic])
    #expect(await eventually { model.kindleVolume == basic })
  }

  @Test func theChosenKindleIsTheOneRead() async {
    let oasis = KindleVolume.fixture(name: "Kindle Oasis")
    let (model, _) = makeModel()
    await model.start()
    monitor.update([kindle, oasis])
    #expect(await eventually { model.destinations.count == 3 })
    #expect(model.kindleVolume == kindle)

    await model.activate(.usb(oasis))

    #expect(model.kindleVolume == oasis)
  }

  @Test func activeKindFollowsTheActiveDestination() async {
    let (model, _) = makeModel()
    await model.start()
    monitor.update([kindle])
    #expect(await eventually { model.destinations == [.usb(kindle), .email(.fixture)] })

    await model.activate(.usb)
    #expect(model.activeKind == .usb)

    await model.activate(.email)
    #expect(model.activeKind == .email)
  }

  @Test func activeKindFallsBackToTheSavedChoice() async {
    let (model, _) = makeModel(AppSettings(activeDestination: .usb))

    await model.start()

    #expect(model.activeDestination == nil)
    #expect(model.activeKind == .usb)
  }

  @Test func namesEveryDestinationTheSameWay() {
    let email = Destination.email(.fixture)
    let oasis = Destination.usb(.fixture(name: "Kindle Oasis"))

    #expect(email.label == "Kindle email")
    #expect(oasis.label == "Kindle Oasis")
    #expect(email.symbol == "envelope.fill")
    #expect(oasis.symbol == "cable.connector")
    #expect(email.symbol == email.kind.symbol)
    #expect(oasis.symbol == oasis.kind.symbol)
    #expect(email.spokenName == "Kindle email")
    #expect(oasis.spokenName == "Kindle Oasis (USB)")
    #expect(email.chipHelp == "Quick-send emails reader@kindle.com")
    #expect(oasis.chipHelp == "Quick-send copies to Kindle Oasis")
  }

  // MARK: Selection

  @Test func filteringDropsHiddenBooksFromTheSelection() async {
    library.result = .success(books(["a"]) + books(["m"], format: .pdf))
    let (model, _) = makeModel()
    await model.appear()
    model.selectAll()

    model.format = .pdf

    #expect(model.selection.ids == [BookID(rawValue: "m")])
  }

  @Test func searchingDropsHiddenBooksFromTheSelection() async {
    library.result = .success([
      .fixture(id: "a", title: "Moby-Dick"), .fixture(id: "b", title: "Dracula"),
    ])
    let (model, _) = makeModel()
    await model.appear()
    model.selectAll()

    model.query = "drac"

    #expect(model.selection.ids == [BookID(rawValue: "b")])
  }

  @Test func switchingToADestinationThatCannotTakeABookDeselectsIt() async {
    library.result = .success([.fixture(id: "big", format: .pdf, sizeBytes: 62_000_000)])
    let (model, _) = makeModel(AppSettings(email: .fixture, activeDestination: .usb))
    monitor.update([kindle])
    await model.start()
    await model.appear()
    #expect(await eventually { model.activeDestination == .usb(kindle) })
    model.click(BookID(rawValue: "big"), .plain)
    #expect(model.selection.count == 1)

    await model.activate(.email)

    #expect(model.selection.isEmpty)
  }

  @Test func knowsWhenAKindleIsPluggedIn() async {
    let (model, _) = makeModel()
    await model.start()
    #expect(!model.isKindlePluggedIn)

    monitor.update([kindle])

    #expect(await eventually { model.isKindlePluggedIn })
  }

  @Test func noticesBokoInstalledWhileSendleRuns() async {
    let converter = FakeFormatConverter(isAvailable: false)
    let (model, _) = makeModel(
      AppSettings(email: .fixture, activeDestination: .usb), converter: converter)
    monitor.update([kindle])
    await model.start()
    await model.appear()
    #expect(await eventually { model.activeDestination == .usb(kindle) })
    #expect(model.items.first?.detail == "Your Kindle can't read EPUB over USB")

    converter.install()
    model.disappear()
    await model.appear()

    #expect(model.items.first?.canSend == true)
  }

  @Test func clearingReportsWhetherThereWasASelection() async {
    let (model, _) = makeModel()
    await model.appear()
    model.click(BookID(rawValue: "a"), .plain)

    #expect(model.clearSelection())
    #expect(!model.clearSelection())
  }

  @Test func arrowKeysMoveByRowsOnlyInTheGrid() async {
    library.result = .success(books(["a", "b", "c", "d", "e", "f"]))
    let (model, _) = makeModel()
    await model.appear()
    model.click(BookID(rawValue: "b"), .plain)

    model.move(.down)
    #expect(model.selection.ids == [BookID(rawValue: "e")])

    await model.setLayout(.list)
    model.move(.down)
    #expect(model.selection.ids == [BookID(rawValue: "f")])
  }

  @Test func sendsTheSelectedBooksInLibraryOrder() async {
    library.result = .success(books(["a", "b", "c"]))
    let (model, _) = makeModel()
    await model.start()
    await model.appear()
    #expect(await eventually { model.activeDestination == .email(.fixture) })

    model.click(BookID(rawValue: "c"), .plain)
    model.click(BookID(rawValue: "a"), .toggle)

    #expect(model.canSend)
    #expect(model.sendHint == "Return to send")
    #expect(model.quickSendHelp == "Send to Kindle email")
    #expect(model.selectedBooks.map(\.id.rawValue) == ["a", "c"])
  }

  @Test func theShelfShowsTheEightNewestBooks() async {
    library.result = .success(
      (0..<10).map {
        .fixture(id: "\($0)", addedAt: Date(timeIntervalSince1970: TimeInterval(1_000 - $0)))
      })
    let (model, _) = makeModel()
    await model.appear()

    #expect(model.recentItems.map(\.id.rawValue) == ["0", "1", "2", "3", "4", "5", "6", "7"])
  }

  // MARK: Sort and A–Z

  func titled(_ titles: [String]) -> [Book] {
    titles.enumerated().map { offset, title in
      .fixture(
        id: title, title: title, addedAt: Date(timeIntervalSince1970: TimeInterval(1_000 - offset))
      )
    }
  }

  @Test func sortsByTitleAndRemembersIt() async {
    library.result = .success(titled(["Moby-Dick", "Emma", "Candide"]))
    let (model, settings) = makeModel()
    await model.appear()
    #expect(model.items.map(\.title) == ["Moby-Dick", "Emma", "Candide"])
    #expect(model.letterJump.index == nil)

    await model.setSort(.title)

    #expect(model.items.map(\.title) == ["Candide", "Emma", "Moby-Dick"])
    #expect(model.letterJump.index?.lettersWithBooks == ["C", "E", "M"])
    #expect(await settings.settings.sort == .title)
  }

  @Test func startsWithTheRememberedSortAndJumpBar() async {
    let (model, _) = makeModel(AppSettings(sort: .author, jumpBar: .compact))

    await model.start()

    #expect(model.sort == .author)
    #expect(model.jumpBar == .compact)
  }

  @Test func followsAJumpBarChangeFromSettings() async throws {
    let (model, settings) = makeModel()
    await model.start()

    try await settings.update { $0.jumpBar = .compact }
    await model.refreshSettings()

    #expect(model.jumpBar == .compact)
  }

  @Test func startsWithTheRememberedControlsAndFollowsAChange() async throws {
    let (model, settings) = makeModel(AppSettings(controls: .attached))
    await model.start()
    #expect(model.controls == .attached)

    try await settings.update { $0.controls = .floating }
    await model.refreshSettings()

    #expect(model.controls == .floating)
  }

  @Test func coversShowTheirFormatUnlessOneFormatIsChosen() async {
    let (model, _) = makeModel()
    await model.start()
    #expect(model.showsFormatOnCovers)

    model.format = .epub

    #expect(!model.showsFormatOnCovers)
  }

  @Test func kindleScopesShowOnlyWhileAKindleIsPluggedIn() async {
    let (model, _) = makeModel()
    await model.start()
    await model.appear()
    #expect(model.filters == [.all, .notSent])

    model.showKindleMatches(.empty)

    #expect(model.filters == [.all, .notSent, .onKindle, .notOnKindle])
  }

  @Test func theKindleMatchesReachTheItemsAndTheirScopes() async {
    let (model, _) = makeModel()
    await model.start()
    await model.appear()
    let onKindle = KindleMatches(
      byBook: [
        BookID(rawValue: "a"): KindleMatch(
          book: .fixture(), confidence: .sure, reason: .sendleName)
      ], onKindle: [:])

    model.showKindleMatches(onKindle)
    #expect(model.items.map(\.marks) == [[.onKindle], []])

    model.filter = .onKindle
    #expect(model.items.map(\.id.rawValue) == ["a"])
    model.filter = .notOnKindle
    #expect(model.items.map(\.id.rawValue) == ["b"])

    model.showKindleMatches(nil)
    #expect(model.filter == .all)
    #expect(model.items.map(\.id.rawValue) == ["a", "b"])
    #expect(model.items.allSatisfy { $0.marks.isEmpty })
  }

  @Test func aKindleThatGoesLeavesAnotherScopeAlone() async {
    let (model, _) = makeModel()
    await model.start()
    await model.appear()
    model.showKindleMatches(.empty)
    model.filter = .notSent

    model.showKindleMatches(nil)

    #expect(model.filter == .notSent)
  }

  @Test func aKindleThatGoesTakesItsScopeWithIt() async {
    let (model, _) = makeModel()
    await model.start()
    await model.appear()
    model.showKindleMatches(.empty)
    model.filter = .onKindle

    model.showKindleMatches(nil)

    #expect(model.filter == .all)
  }

  @Test func hidesTheFormatUnderEveryFilterWhenTheSettingIsOff() async {
    let (model, _) = makeModel(AppSettings(email: .fixture, showsFormat: false))
    await model.start()

    for filter in LibraryFilter.allCases {
      model.filter = filter
      #expect(!model.showsFormatOnCovers)
    }
  }

  @Test func followsAFormatChangeFromSettings() async throws {
    let (model, settings) = makeModel()
    await model.start()
    #expect(model.showsFormatOnCovers)

    try await settings.update { $0.showsFormat = false }
    await model.refreshSettings()

    #expect(!model.showsFormatOnCovers)
  }

  @Test func indexesOnlyTheBooksTheSearchShows() async {
    library.result = .success(titled(["Moby-Dick", "Emma", "Candide"]))
    let (model, _) = makeModel(AppSettings(email: .fixture, sort: .title))
    await model.start()
    await model.appear()

    model.query = "e"

    #expect(model.items.map(\.title) == ["Candide", "Emma", "Moby-Dick"])
    model.query = "mm"
    #expect(model.letterJump.index?.lettersWithBooks == ["E"])
  }

  @Test func theShelfShowsTheNewestBooksWhateverTheSort() async {
    library.result = .success(titled(["Moby-Dick", "Emma", "Candide"]))
    let (model, _) = makeModel(AppSettings(email: .fixture, sort: .title))
    await model.start()
    await model.appear()

    #expect(model.recentItems.map(\.title) == ["Moby-Dick", "Emma", "Candide"])
  }

  @Test func aLetterJumpsToItsFirstBookAndTheRailFollowsTheScroll() async {
    library.result = .success(titled(["Moby-Dick", "Emma", "Candide", "Middlemarch"]))
    let (model, _) = makeModel(AppSettings(email: .fixture, sort: .title))
    await model.start()
    await model.appear()

    model.letterJump.jump(to: "M")
    #expect(model.letterJump.top == BookID(rawValue: "Middlemarch"))
    #expect(model.letterJump.currentLetter == "M")

    model.letterJump.jump(to: "D")
    #expect(model.letterJump.top == BookID(rawValue: "Emma"))

    model.letterJump.top = BookID(rawValue: "Candide")
    #expect(model.letterJump.currentLetter == "C")
  }

  @Test func aNewSortFilterOrSearchStartsAtTheTop() async {
    library.result = .success(titled(["Moby-Dick", "Emma", "Candide"]))
    let (model, _) = makeModel()
    await model.start()
    await model.appear()

    model.letterJump.top = BookID(rawValue: "Emma")
    await model.setSort(.title)
    #expect(model.letterJump.top == nil)
    #expect(model.scrollToTopRequests == 1)

    model.format = .epub
    model.query = "e"
    #expect(model.scrollToTopRequests == 3)
  }

  @Test func reloadsAndRepeatedChoicesKeepTheScroll() async {
    library.result = .success(titled(["Moby-Dick", "Emma", "Candide"]))
    let (model, _) = makeModel()
    await model.start()
    await model.appear()
    model.letterJump.top = BookID(rawValue: "Emma")

    model.filter = .all
    model.query = ""
    await model.setSort(.recent)
    await model.reload()
    await model.refreshHistory()

    #expect(model.letterJump.top == BookID(rawValue: "Emma"))
    #expect(model.scrollToTopRequests == 0)
  }

  @Test func draggingAlongTheRailShowsTheLetterAndJumps() async {
    library.result = .success(titled(["Moby-Dick", "Emma"]))
    let (model, _) = makeModel(AppSettings(email: .fixture, sort: .title))
    await model.start()
    await model.appear()

    model.letterJump.drag(to: "E")
    #expect(model.letterJump.draggedLetter == "E")
    #expect(model.letterJump.top == BookID(rawValue: "Emma"))

    model.letterJump.endDrag()
    #expect(model.letterJump.draggedLetter == nil)
  }

  @Test func theRailShowsWhileSortedByTitleOrAuthor() async {
    library.result = .success(titled(["Moby-Dick", "Emma"]))
    let (model, _) = makeModel()
    await model.start()
    await model.appear()
    #expect(!model.letterJump.isShown)

    await model.setSort(.author)
    #expect(model.letterJump.isShown)
    #expect(model.letterJump.letters(model.jumpBar) == LibraryOrder.letters)

    model.query = "nothing like this"
    #expect(!model.letterJump.isShown)
  }

  @Test func theCompactRailListsOnlyLettersWithBooks() async {
    library.result = .success(titled(["Moby-Dick", "Emma"]))
    let (model, _) = makeModel(AppSettings(email: .fixture, sort: .title, jumpBar: .compact))
    await model.start()
    await model.appear()

    #expect(model.letterJump.letters(model.jumpBar) == ["E", "M"])
  }

  @Test func namesTheSorts() {
    #expect(LibrarySort.allCases.map(\.title) == ["Recently added", "Title", "Author"])
  }

  /// With 500 books, building the items on every read made each render slow.
  @Test func buildsTheItemsOncePerChange() async {
    let builds = OSAllocatedUnfairLock(initialState: 0)
    let settings = InMemorySettingsStore(AppSettings(email: .fixture))
    let model = LibraryViewModel(
      loadLibrary: LoadLibrary(library: library, inspector: StubProtectionInspector()),
      observeDestinations: ObserveDestinations(monitor: monitor, settings: settings),
      settings: settings, history: history, converter: FakeFormatConverter(isAvailable: false),
      now: {
        builds.withLock { $0 += 1 }
        return Date(timeIntervalSince1970: 1_800_000_000)
      })
    await model.appear()
    let afterLoading = builds.withLock { $0 }

    for _ in 0..<10 { _ = model.items.count + model.recentItems.count }
    #expect(builds.withLock { $0 } == afterLoading)

    model.query = "moby"
    #expect(builds.withLock { $0 } == afterLoading + 1)

    await model.reload()
    #expect(builds.withLock { $0 } == afterLoading + 2)
  }
}
