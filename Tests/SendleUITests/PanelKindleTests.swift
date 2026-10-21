import Foundation
import SendleDomain
import SendleTestSupport
import SendleUI
import Testing

@MainActor @Suite(.timeLimit(.minutes(1)))
struct PanelKindleTests {
  let harness = PanelHarness()

  /// A Kindle holding Moby-Dick under another author: only an email send can make it match.
  let emailedCopy = KindleBook.fixture(
    path: "Downloads/Items01/Moby-Dick_0123456789abcdef0123456789abcdef.kfx", title: "Moby-Dick",
    authors: ["Another Author"], source: .email)

  @Test func theSwitchShowsBothCounts() async {
    let (panel, _) = harness.makePanel(kindle: FakeKindleLibrary(.success(.fixture([.fixture()]))))
    #expect(panel.switchTitle(.kindle) == "On Kindle")
    await panel.launch()
    await panel.panelDidOpen()
    harness.monitor.update([.fixture()])
    #expect(await eventually { panel.switchTitle(.kindle) == "On Kindle · 1" })
    #expect(panel.switchTitle(.library) == "Library · 2")
  }

  @Test func showsTheKindleSideOnlyWhileOneIsPluggedIn() async {
    let (panel, _) = harness.makePanel()
    await panel.launch()
    panel.showSide(.kindle)
    #expect(panel.side == .library)
    harness.monitor.update([.fixture()])
    #expect(await eventually { panel.kindle.state == .loaded })
    panel.showSide(.kindle)
    #expect(panel.side == .kindle)
  }

  @Test func unpluggingTheKindleGoesBackToTheLibrary() async {
    let (panel, _) = harness.makePanel()
    await panel.launch()
    harness.monitor.update([.fixture()])
    #expect(await eventually { panel.library.kindleMatches != nil })
    panel.showSide(.kindle)
    harness.monitor.update([])
    #expect(await eventually { panel.side == .library && panel.library.kindleMatches == nil })
  }

  @Test func unpluggingTheKindleMidListingGoesBackToTheLibrary() async {
    let gate = Signal()
    let kindle = FakeKindleLibrary(.success(.fixture([.fixture()])))
    kindle.gate = gate
    let (panel, _) = harness.makePanel(kindle: kindle)
    await panel.launch()
    harness.monitor.update([.fixture()])
    #expect(await eventually { panel.kindle.state == .reading(done: 0, total: 0) })
    panel.showSide(.kindle)

    harness.monitor.update([])
    #expect(await eventually { panel.side == .library && panel.kindle.state == .idle })
    await gate.fire()
    await panel.kindle.rematch()

    #expect(panel.kindle.listing == nil)
    #expect(panel.library.kindleMatches == nil)
    #expect(panel.side == .library)
  }

  @Test func theKindleFollowsTheDestinationsVolume() async {
    let kindle = FakeKindleLibrary()
    let oasis = KindleVolume.fixture(name: "Kindle Oasis")
    let (panel, _) = harness.makePanel(kindle: kindle)
    await panel.launch()
    harness.monitor.update([.fixture(), oasis])
    #expect(await eventually { panel.kindle.volume == .fixture() })
    await panel.library.activate(.usb(oasis))
    #expect(await eventually { panel.kindle.volume == oasis })
    #expect(await eventually { kindle.listings == 2 })
  }

  @Test func theKindleSideSharesTheLibrarysSort() async {
    let (panel, _) = harness.makePanel()
    await panel.launch()
    await panel.library.setSort(.author)
    #expect(panel.kindle.sort == .author)
  }

  @Test func theSavedSortReachesTheKindleAtStart() async {
    let (panel, _) = harness.makePanel(AppSettings(email: .fixture, sort: .title))
    await panel.launch()
    #expect(panel.kindle.sort == .title)
  }

  @Test func theSavedAuthorSortReachesTheKindleAtStart() async {
    let (panel, _) = harness.makePanel(AppSettings(email: .fixture, authorSort: .firstName))
    await panel.launch()
    #expect(panel.kindle.authorSort == .firstName)
  }

  @Test func theKindleSideFollowsTheAuthorSortSetting() async {
    let (panel, _) = harness.makePanel()
    await panel.launch()
    #expect(panel.kindle.authorSort == .surname)
    await panel.settings.setAuthorSort(.firstName)
    #expect(await eventually { panel.kindle.authorSort == .firstName })
    await panel.settings.setAuthorSort(.surname)
    #expect(await eventually { panel.kindle.authorSort == .surname })
  }

  @Test func kindleCoversShowTheirFormatInEveryScopeUntilOneFormatIsChosen() async {
    let mixed = FakeKindleLibrary(.success(.fixture([.fixture(), .fixture(path: "notes.txt")])))
    let (panel, _) = harness.makePanel(kindle: mixed)
    await panel.launch()
    harness.monitor.update([.fixture()])
    #expect(await eventually { panel.kindle.state == .loaded })

    for scope in KindleScope.allCases {
      panel.kindle.scope = scope
      #expect(panel.showsFormatOnKindleCovers)
    }
    panel.kindle.format = "txt"
    #expect(!panel.showsFormatOnKindleCovers)
  }

  @Test func theShowFormatSettingAppliesToKindleCovers() async {
    let (panel, _) = harness.makePanel(AppSettings(email: .fixture, showsFormat: false))
    await panel.launch()
    harness.monitor.update([.fixture()])
    #expect(await eventually { panel.kindle.state == .loaded })

    #expect(!panel.showsFormatOnKindleCovers)
    await panel.settings.setShowsFormat(true)
    #expect(await eventually { panel.showsFormatOnKindleCovers })
  }

  @Test func commandRRefreshesOnlyTheKindleSide() async {
    let kindle = FakeKindleLibrary()
    let (panel, _) = harness.makePanel(kindle: kindle)
    await panel.launch()
    harness.monitor.update([.fixture()])
    #expect(await eventually { kindle.listings == 1 })
    #expect(!panel.handle(KeyInput(.character("r"), command: true)))
    panel.showSide(.kindle)
    #expect(panel.handle(KeyInput(.character("r"), command: true)))
    #expect(await eventually { kindle.listings == 2 })
  }

  @Test func theKindleSideTakesNoSelectionKeys() async {
    let (panel, _) = harness.makePanel()
    await panel.launch()
    harness.monitor.update([.fixture()])
    #expect(await eventually { panel.kindle.state == .loaded })
    panel.showSide(.kindle)
    #expect(!panel.handle(KeyInput(.character("a"), command: true)))
    #expect(!panel.handle(KeyInput(.down)))
    #expect(!panel.handle(KeyInput(.returnKey)))
    #expect(panel.library.selection.isEmpty)
  }

  @Test func escapeClearsTheKindleSearchBeforeClosing() async {
    let (panel, _) = harness.makePanel()
    await panel.launch()
    harness.monitor.update([.fixture()])
    #expect(await eventually { panel.kindle.state == .loaded })
    panel.showSide(.kindle)
    panel.kindle.query = "dracula"
    panel.library.query = "moby"
    panel.escape()
    #expect(panel.kindle.query.isEmpty)
    #expect(panel.library.query == "moby")
    #expect(harness.system.closedPanel == 0)
    panel.escape()
    #expect(harness.system.closedPanel == 1)
  }

  @Test func aUSBSendReadsTheKindleAgain() async {
    harness.library.result = .success([.fixture(id: "a", format: .pdf)])
    let kindle = FakeKindleLibrary()
    let (panel, _) = harness.makePanel(
      AppSettings(email: .fixture, activeDestination: .usb), kindle: kindle)
    harness.monitor.update([.fixture()])
    await panel.launch()
    await panel.panelDidOpen()
    #expect(await eventually { kindle.listings == 1 && panel.kindle.state == .loaded })

    await panel.quickSend(BookID(rawValue: "a"))
    await panel.queue.waitUntilFinished()

    #expect(kindle.listings == 3)
  }

  @Test func aBookJustCopiedNeverShowsAsMissingFromTheKindle() async {
    let (panel, kindle, _) = await harness.pluggedInPanel(listing: [])
    await panel.quickSend(BookID(rawValue: "b"))
    let gate = Signal()
    kindle.gate = gate
    kindle.result = .success(
      .fixture([
        .fixture(
          path: "Dracula - Bram Stoker.pdf", title: "Dracula", authors: ["Bram Stoker"],
          source: .sendle, asin: "SNDRACULA1", asinFollowsFileName: true)
      ]))
    func marks() -> [BookMark]? {
      panel.library.items.first { $0.id == BookID(rawValue: "b") }?.marks
    }

    #expect(await eventually { kindle.listings == 3 })
    #expect(marks()?.contains(.route(.usb, dimmed: true)) == false)
    await gate.fire()
    await panel.queue.waitUntilFinished()
    #expect(await eventually { marks() == [.onKindle] })
  }

  @Test func anEmailSendOnlyMatchesAgain() async {
    let kindle = FakeKindleLibrary(.success(.fixture([emailedCopy])))
    let (panel, _) = harness.makePanel(kindle: kindle)
    harness.monitor.update([.fixture()])
    await panel.launch()
    await panel.panelDidOpen()
    #expect(await eventually { panel.kindle.state == .loaded && panel.kindle.matches != nil })
    #expect(panel.library.kindleMatches?.byBook[BookID(rawValue: "a")] == nil)

    await panel.quickSend(BookID(rawValue: "a"))
    await panel.queue.waitUntilFinished()

    #expect(kindle.listings == 1)
    #expect(panel.library.kindleMatches?.byBook[BookID(rawValue: "a")]?.reason == .emailedTitle)
  }

  @Test func ejectShowsInsideTheChipOnHover() async {
    let (panel, _) = harness.makePanel()
    await panel.launch()
    let kindle = KindleVolume.fixture()
    #expect(!panel.showsEject(in: kindle))
    panel.hoveredChip = kindle
    #expect(panel.showsEject(in: kindle))
    #expect(!panel.showsEject(in: .fixture(name: "Kindle Oasis")))
    panel.hoveredChip = nil
    #expect(!panel.showsEject(in: kindle))
  }

  @Test func ejectStaysInTheChipWhileTheKindleEjects() async {
    let gate = Signal()
    let kindle = KindleVolume.fixture()
    let ejector = FakeKindleEjector(gate: gate)
    let (panel, _) = harness.makePanel(ejector: ejector)
    harness.monitor.update([kindle])
    await panel.launch()
    #expect(await eventually { panel.library.isKindlePluggedIn })

    let ejecting = Task { await panel.eject(kindle) }
    #expect(await eventually { panel.ejecting == kindle })
    #expect(panel.showsEject(in: kindle))
    #expect(panel.ejectActionName(for: kindle) == nil)

    await gate.fire()
    await ejecting.value
    #expect(!panel.showsEject(in: kindle))
  }

  @Test func ejectIsAnAccessibilityActionExceptDuringACopy() async {
    let kindle = KindleVolume.fixture()
    harness.library.result = .success([.fixture(id: "a", format: .pdf)])
    let channel = FakeDeliveryChannel(.hangUntilCancelled)
    let (panel, _) = harness.makePanel(
      AppSettings(email: .fixture, activeDestination: .usb), channel: channel)
    harness.monitor.update([kindle])
    await panel.launch()
    await panel.panelDidOpen()
    #expect(await eventually { panel.library.activeDestination == .usb(kindle) })
    #expect(panel.ejectActionName(for: kindle) == "Eject Kindle")

    await panel.quickSend(BookID(rawValue: "a"))
    await channel.waitUntilDeliveryStarts()
    #expect(panel.ejectActionName(for: kindle) == nil)

    panel.queue.cancel()
    await panel.queue.waitUntilFinished()
    #expect(panel.ejectActionName(for: kindle) == "Eject Kindle")
  }

  @Test func ejectShowsInsideTheChipWhileItHasKeyboardFocus() async {
    let (panel, _) = harness.makePanel()
    await panel.launch()
    let kindle = KindleVolume.fixture()
    panel.focusedChip = kindle
    #expect(panel.showsEject(in: kindle))
    #expect(!panel.showsEject(in: .fixture(name: "Kindle Oasis")))
    panel.focusedChip = nil
    #expect(!panel.showsEject(in: kindle))
  }

  @Test func closingThePanelClearsTheChipUnderThePointer() async {
    let (panel, _) = harness.makePanel()
    await panel.launch()
    panel.hoveredChip = .fixture()
    panel.focusedChip = .fixture()
    panel.panelDidClose()
    #expect(!panel.showsEject(in: .fixture()))
  }

  // MARK: Duplicates

  /// Sendle's own PDF of Moby-Dick, the library's book "a".
  let sendlesPDF = KindleBook.fixture(
    path: "Moby-Dick - Herman Melville.pdf", source: .sendle, asin: "SNMOBYDICK",
    asinFollowsFileName: true)

  @Test func aUSBSendOfABookOnTheKindleAsksFirst() async {
    let (panel, _, _) = await harness.pluggedInPanel(listing: [sendlesPDF])
    panel.library.selectAll()

    await panel.sendSelection()

    #expect(panel.duplicateReview?.counter == "1 of 1")
    #expect(panel.duplicateReview?.current.replace == .inPlace)
    #expect(!panel.queue.isRunning)
    #expect(panel.queue.isEmpty)
    #expect(panel.route == .library)
  }

  @Test func quickSendAsksToo() async {
    let (panel, _, _) = await harness.pluggedInPanel(listing: [sendlesPDF])

    await panel.quickSend(BookID(rawValue: "a"))

    #expect(panel.duplicateReview != nil)
    #expect(panel.queue.isEmpty)
  }

  @Test func skipLeavesTheBookOutAndSendsTheRest() async {
    let (panel, _, channel) = await harness.pluggedInPanel(listing: [sendlesPDF])
    panel.library.selectAll()
    await panel.sendSelection()

    panel.choose(.skip)
    await panel.waitUntilReviewed()
    await panel.queue.waitUntilFinished()

    #expect(panel.duplicateReview == nil)
    #expect(panel.queue.rows.map(\.id.rawValue) == ["b"])
    #expect(channel.deliveries.map(\.name) == ["Dracula - Bram Stoker"])
    #expect(panel.route == .queue)
    #expect(panel.library.selection.isEmpty)
  }

  @Test func skippingEveryBookSendsNothingAndKeepsTheSelection() async {
    let (panel, _, channel) = await harness.pluggedInPanel(listing: [sendlesPDF])
    panel.click(BookID(rawValue: "a"), .plain)
    await panel.sendSelection()

    panel.choose(.skip)

    #expect(panel.duplicateReview == nil)
    await panel.waitUntilReviewed()
    await panel.queue.waitUntilFinished()
    #expect(panel.checkingKindle == nil)
    #expect(channel.deliveries.isEmpty)
    #expect(panel.queue.isEmpty)
    #expect(panel.route == .library)
    #expect(panel.library.selection.ids == [BookID(rawValue: "a")])
  }

  @Test func keepBothSendsUnderTheNextFreeName() async {
    let taken = KindleBook.fixture(path: "Moby-Dick - Herman Melville (2).azw3")
    let (panel, _, channel) = await harness.pluggedInPanel(listing: [sendlesPDF, taken])
    await panel.quickSend(BookID(rawValue: "a"))

    panel.choose(.keepBoth)
    await panel.waitUntilReviewed()
    await panel.queue.waitUntilFinished()

    #expect(channel.deliveries.map(\.name) == ["Moby-Dick - Herman Melville (3)"])
  }

  @Test func applyingKeepBothToTheRestNamesEveryCopy() async {
    let twin = KindleBook.fixture(
      path: "Dracula - Bram Stoker.pdf", title: "Dracula", authors: ["Bram Stoker"],
      source: .sendle, asin: "SNDRACULA1", asinFollowsFileName: true)
    let (panel, _, channel) = await harness.pluggedInPanel(listing: [sendlesPDF, twin])
    panel.library.selectAll()
    await panel.sendSelection()
    panel.duplicateReview?.appliesToRest = true

    panel.choose(.keepBoth)
    await panel.waitUntilReviewed()
    await panel.queue.waitUntilFinished()

    #expect(
      channel.deliveries.map(\.name).sorted()
        == ["Dracula - Bram Stoker (2)", "Moby-Dick - Herman Melville (2)"])
  }

  @Test func replaceOverwritesSendlesCopyInPlace() async {
    let (panel, _, channel) = await harness.pluggedInPanel(listing: [sendlesPDF])
    await panel.quickSend(BookID(rawValue: "a"))

    panel.chooseDefault()
    await panel.waitUntilReviewed()
    await panel.queue.waitUntilFinished()

    #expect(channel.deliveries.map(\.name) == ["Moby-Dick - Herman Melville"])
  }

  @Test func replaceKeepsTheASINOfTheKindlesCopy() async {
    let older = KindleBook.fixture(
      path: "Moby-Dick - Herman Melville.azw3", source: .sendle, asin: "SNMOBYDICK",
      asinFollowsFileName: true)
    let (panel, _, channel) = await harness.pluggedInPanel(
      listing: [older], books: [.fixture(id: "a")], converts: true)
    await panel.quickSend(BookID(rawValue: "a"))

    panel.chooseDefault()
    await panel.waitUntilReviewed()
    await panel.queue.waitUntilFinished()

    #expect(channel.deliveries.map(\.name) == ["Moby-Dick - Herman Melville"])
    #expect(channel.deliveries.map(\.file.asin) == ["SNMOBYDICK"])
  }

  /// Moby-Dick's edition, the library's EPUB "a".
  let mobyEdition = [BookID(rawValue: "a"): Edition(key: "urn:uuid:moby-dick")]

  @Test func keepBothForAnEditedBookUsesItsNewNameWithoutANumber() async {
    let older = KindleBook.fixture(
      path: "Moby-Dick - Herman Melville.azw3", source: .sendle,
      asin: "SN:edition:urn:uuid:moby-dick")
    let (panel, _, channel) = await harness.pluggedInPanel(
      listing: [older], books: [.fixture(id: "a")], converts: true,
      edits: MetadataEdits(books: [BookID(rawValue: "a"): BookEdit(title: "The Whale")]),
      editions: mobyEdition)
    await panel.quickSend(BookID(rawValue: "a"))
    #expect(panel.duplicateReview?.choices == [.skip, .keepBoth])

    panel.choose(.keepBoth)
    await panel.waitUntilReviewed()
    await panel.queue.waitUntilFinished()

    #expect(channel.deliveries.map(\.name) == ["The Whale - Herman Melville"])
    #expect(channel.deliveries.map(\.file.asinSeed) == ["edition:urn:uuid:moby-dick#2"])
  }

  @Test func keepBothForAnEditedBookWhoseNameIsTakenIsNumbered() async {
    let older = KindleBook.fixture(
      path: "Moby-Dick - Herman Melville.pdf", source: .sendle, asin: "SNMOBYDICK",
      asinFollowsFileName: true)
    let namesake = KindleBook.fixture(path: "The Whale - Herman Melville.pdf", title: "Other")
    let (panel, _, channel) = await harness.pluggedInPanel(
      listing: [older, namesake], books: [.fixture(id: "a", format: .pdf)],
      edits: MetadataEdits(books: [BookID(rawValue: "a"): BookEdit(title: "The Whale")]))
    await panel.quickSend(BookID(rawValue: "a"))

    panel.choose(.keepBoth)
    await panel.waitUntilReviewed()
    await panel.queue.waitUntilFinished()

    #expect(channel.deliveries.map(\.name) == ["The Whale - Herman Melville (2)"])
  }

  @Test func aSendWithoutDuplicatesStillGetsFreeASINs() async {
    let renamed = KindleBook.fixture(
      path: "Leviathan - Someone Else.azw3", title: "Leviathan", authors: ["Someone Else"],
      source: .sendle, asin: "SN:edition:urn:uuid:moby-dick")
    let (panel, _, channel) = await harness.pluggedInPanel(
      listing: [renamed], books: [.fixture(id: "a")], converts: true, editions: mobyEdition)

    await panel.quickSend(BookID(rawValue: "a"))
    await panel.queue.waitUntilFinished()

    #expect(panel.duplicateReview == nil)
    #expect(channel.deliveries.map(\.name) == ["Moby-Dick - Herman Melville"])
    #expect(channel.deliveries.map(\.file.asinSeed) == ["edition:urn:uuid:moby-dick#2"])
  }

  @Test func aCopySendleDidNotNameOffersOnlySkipAndKeepBoth() async {
    let byHand = KindleBook.fixture(path: "Moby Dick.pdf")
    let (panel, _, channel) = await harness.pluggedInPanel(listing: [byHand])
    await panel.quickSend(BookID(rawValue: "a"))

    #expect(panel.duplicateReview?.choices == [.skip, .keepBoth])
    panel.chooseDefault()

    #expect(panel.duplicateReview == nil)
    await panel.waitUntilReviewed()
    await panel.queue.waitUntilFinished()
    #expect(panel.checkingKindle == nil)
    #expect(channel.deliveries.isEmpty)
    #expect(panel.queue.isEmpty)
  }

  /// Calibre's copy of Moby-Dick, in a folder of its own.
  let calibreCopy = KindleBook.fixture(
    path: "Herman Melville/Moby-Dick (7)/Moby-Dick - Herman Melville.pdf", source: .calibre,
    asin: "0f8c2a54-1d5e-4a39-9b64-3f7a1c2d8e90")

  @Test func replacingACalibreCopySendsItUnderSendlesNameThenRemovesIt() async {
    let remover = FakeKindleBookRemover()
    let (panel, _, channel) = await harness.pluggedInPanel(
      listing: [calibreCopy], remover: remover)
    await panel.quickSend(BookID(rawValue: "a"))
    #expect(panel.duplicateReview?.current.replace == .removesOther)

    panel.choose(.replace)
    await panel.waitUntilReviewed()
    await panel.queue.waitUntilFinished()

    #expect(channel.deliveries.map(\.name) == ["Moby-Dick - Herman Melville"])
    #expect(remover.holds == [calibreCopy])
    #expect(
      harness.log.messages(in: .usb).first
        == "Replacing documents/\(calibreCopy.id.relativePath) on Kindle")
  }

  @Test func aReplacementNeverTakesTheOldCopysASIN() async {
    let calibre = KindleBook.fixture(
      path: "Herman Melville/Moby-Dick (7)/Moby-Dick - Herman Melville.azw3", source: .calibre,
      asin: "0f8c2a54-1d5e-4a39-9b64-3f7a1c2d8e90")
    let (panel, _, channel) = await harness.pluggedInPanel(
      listing: [calibre], books: [.fixture(id: "a")], converts: true,
      remover: FakeKindleBookRemover())
    await panel.quickSend(BookID(rawValue: "a"))

    panel.choose(.replace)
    await panel.waitUntilReviewed()
    await panel.queue.waitUntilFinished()

    #expect(channel.deliveries.map(\.file.asin) == [nil])
  }

  @Test func aReplacementWhoseNameIsTakenGoesUnderTheNextFreeOne() async {
    let remover = FakeKindleBookRemover()
    let taken = KindleBook.fixture(
      path: "Moby-Dick - Herman Melville.azw3", title: "Other", authors: ["Someone Else"])
    let (panel, _, channel) = await harness.pluggedInPanel(
      listing: [calibreCopy, taken], remover: remover)
    await panel.quickSend(BookID(rawValue: "a"))

    panel.choose(.replace)
    await panel.waitUntilReviewed()
    await panel.queue.waitUntilFinished()

    #expect(channel.deliveries.map(\.name) == ["Moby-Dick - Herman Melville (2)"])
    #expect(remover.holds == [calibreCopy])
    #expect(
      harness.log.messages(in: .usb).contains(
        "Sendle's name for Moby-Dick is taken, so it goes as Moby-Dick - Herman Melville (2)"))
  }

  @Test func aReplacementMayTakeTheNameOfTheCopyItRemoves() async {
    let remover = FakeKindleBookRemover()
    let (panel, _, channel) = await harness.pluggedInPanel(
      listing: [sendlesPDF], books: [.fixture(id: "a")], converts: true, remover: remover)
    await panel.quickSend(BookID(rawValue: "a"))
    #expect(panel.duplicateReview?.current.replace == .removesOther)

    panel.choose(.replace)
    await panel.waitUntilReviewed()
    await panel.queue.waitUntilFinished()

    #expect(channel.deliveries.map(\.name) == ["Moby-Dick - Herman Melville"])
    #expect(remover.holds == [sendlesPDF])
    #expect(!harness.log.messages(in: .usb).contains { $0.contains("is taken") })
  }

  @Test func closingTheSheetSendsNothing() async {
    let (panel, _, channel) = await harness.pluggedInPanel(listing: [sendlesPDF])
    panel.library.selectAll()
    await panel.sendSelection()

    panel.cancelReview()

    #expect(panel.duplicateReview == nil)
    #expect(channel.deliveries.isEmpty)
    #expect(panel.queue.isEmpty)
    #expect(panel.library.selection.count == 2)
  }

  @Test func returnTakesTheDefaultAndEscapeClosesTheSheet() async {
    let (panel, _, channel) = await harness.pluggedInPanel(listing: [sendlesPDF])
    await panel.quickSend(BookID(rawValue: "a"))

    #expect(panel.handle(KeyInput(.escape)))
    #expect(panel.duplicateReview == nil)
    #expect(harness.system.closedPanel == 0)
    #expect(channel.deliveries.isEmpty)

    await panel.quickSend(BookID(rawValue: "a"))
    #expect(panel.handle(KeyInput(.returnKey)))
    await panel.waitUntilReviewed()
    await panel.queue.waitUntilFinished()
    #expect(channel.deliveries.map(\.name) == ["Moby-Dick - Herman Melville"])
  }

  @Test func aHeldReturnDoesNotWalkThroughTheSheet() async {
    let (panel, _, channel) = await harness.pluggedInPanel(listing: [sendlesPDF])
    await panel.quickSend(BookID(rawValue: "a"))

    #expect(panel.handle(KeyInput(.returnKey, isRepeat: true)))

    #expect(panel.duplicateReview != nil)
    #expect(channel.deliveries.isEmpty)
  }

  @Test func theLibraryIgnoresItsKeysBehindTheSheet() async {
    let (panel, _, _) = await harness.pluggedInPanel(listing: [sendlesPDF])
    await panel.quickSend(BookID(rawValue: "a"))

    #expect(!panel.handle(KeyInput(.character("a"), command: true)))
    #expect(!panel.handle(KeyInput(.down)))
    #expect(panel.library.selection.isEmpty)
  }

  @Test func anEmailSendNeverAsks() async {
    harness.library.result = .success([.fixture(id: "a", format: .pdf)])
    let kindle = FakeKindleLibrary(.success(.fixture([sendlesPDF])))
    let (panel, _) = harness.makePanel(kindle: kindle)
    harness.monitor.update([.fixture()])
    await panel.launch()
    await panel.panelDidOpen()
    #expect(await eventually { panel.kindle.state == .loaded && panel.kindle.matches != nil })

    await panel.quickSend(BookID(rawValue: "a"))

    #expect(panel.duplicateReview == nil)
    #expect(panel.route == .queue)
    #expect(panel.queue.destination?.kind == .email)
  }

  @Test func aBookAddedSinceTheLastReadIsStillFound() async {
    let (panel, kindle, _) = await harness.pluggedInPanel(listing: [])
    #expect(panel.kindle.matches?.byBook[BookID(rawValue: "a")] == nil)
    kindle.result = .success(.fixture([sendlesPDF]))

    await panel.quickSend(BookID(rawValue: "a"))

    #expect(panel.duplicateReview != nil)
  }

  @Test func aKindleThatCannotBeReadSendsAsBefore() async {
    let (panel, kindle, channel) = await harness.pluggedInPanel(listing: [sendlesPDF])
    kindle.result = .failure(.unreadable("I/O error"))

    await panel.quickSend(BookID(rawValue: "a"))
    await panel.queue.waitUntilFinished()

    #expect(panel.duplicateReview == nil)
    #expect(channel.deliveries.map(\.name) == ["Moby-Dick - Herman Melville"])
    #expect(
      harness.log.summary.contains(
        "warning USB Couldn't check Kindle for duplicates: I/O error; sending as before"))
  }

  @Test func eachDecisionIsLogged() async {
    let twin = KindleBook.fixture(
      path: "Dracula - Bram Stoker.pdf", title: "Dracula", authors: ["Bram Stoker"],
      source: .sendle, asin: "SNDRACULA1", asinFollowsFileName: true)
    let (panel, _, _) = await harness.pluggedInPanel(listing: [sendlesPDF, twin])
    panel.library.selectAll()
    await panel.sendSelection()

    for _ in 1...2 {
      panel.choose(panel.duplicateReview?.current.book.title == "Moby-Dick" ? .skip : .keepBoth)
    }
    await panel.waitUntilReviewed()
    await panel.queue.waitUntilFinished()

    #expect(
      Set(harness.log.messages(in: .usb).prefix(2)) == [
        "Skipped Moby-Dick: Kindle already has it",
        "Keeping both: Dracula goes as Dracula - Bram Stoker (2)",
      ])
  }

  @Test func aReplaceIsLogged() async {
    let (panel, _, _) = await harness.pluggedInPanel(listing: [sendlesPDF])
    await panel.quickSend(BookID(rawValue: "a"))

    panel.chooseDefault()
    await panel.waitUntilReviewed()
    await panel.queue.waitUntilFinished()

    #expect(
      harness.log.messages(in: .usb).first
        == "Replacing documents/Moby-Dick - Herman Melville.pdf on Kindle")
  }

  @Test func aBookNotOnTheKindleSendsAtOnce() async {
    let (panel, _, channel) = await harness.pluggedInPanel(listing: [sendlesPDF])

    await panel.quickSend(BookID(rawValue: "b"))
    await panel.queue.waitUntilFinished()

    #expect(panel.duplicateReview == nil)
    #expect(channel.deliveries.map(\.name) == ["Dracula - Bram Stoker"])
  }

  @Test func unpluggingTheKindleDropsTheSheet() async {
    let (panel, _, channel) = await harness.pluggedInPanel(listing: [sendlesPDF])
    await panel.quickSend(BookID(rawValue: "a"))
    #expect(panel.duplicateReview != nil)

    harness.monitor.update([])

    #expect(await eventually { panel.duplicateReview == nil })
    #expect(channel.deliveries.isEmpty)
    #expect(panel.queue.isEmpty)
    #expect(panel.notice == ProblemPresenter.kindleChangedWhileChecking(.fixture()))
  }

  @Test func aSecondSendWhileTheKindleIsBeingReadIsIgnored() async {
    let (panel, kindle, channel) = await harness.pluggedInPanel(listing: [])
    let gate = Signal()
    kindle.gate = gate
    let first = Task { await panel.quickSend(BookID(rawValue: "b")) }
    #expect(await eventually { panel.kindle.state == .reading(done: 0, total: 0) })

    await panel.quickSend(BookID(rawValue: "a"))
    await gate.fire()
    await first.value
    await panel.queue.waitUntilFinished()

    #expect(channel.deliveries.map(\.name) == ["Dracula - Bram Stoker"])
  }

  // MARK: Two Kindles

  let oasis = KindleVolume.fixture(name: "Kindle Oasis")

  /// Two PDFs, two Kindles with their own books, USB to the first, and the first read.
  func twoKindlePanel(
    first: [KindleBook], second: [KindleBook]
  ) async -> (panel: PanelModel, kindle: FakeKindleLibrary, channel: FakeDeliveryChannel) {
    harness.library.result = .success([
      .fixture(id: "a", format: .pdf),
      .fixture(id: "b", title: "Dracula", author: "Bram Stoker", format: .pdf),
    ])
    let kindle = FakeKindleLibrary(.success(.fixture(first)))
    kindle.setResult(.success(.fixture(second)), for: oasis)
    let channel = FakeDeliveryChannel()
    let (panel, _) = harness.makePanel(
      AppSettings(email: .fixture, activeDestination: .usb), channel: channel, kindle: kindle)
    harness.monitor.update([.fixture(), oasis])
    await panel.launch()
    await panel.panelDidOpen()
    _ = await eventually {
      panel.library.activeDestination == .usb(.fixture()) && panel.kindle.matches != nil
    }
    return (panel, kindle, channel)
  }

  @Test func switchingTheKindleWhileItIsCheckedSendsNothing() async {
    let (panel, kindle, channel) = await twoKindlePanel(first: [sendlesPDF], second: [])
    let gate = Signal()
    kindle.gate = gate
    let sending = Task { await panel.quickSend(BookID(rawValue: "a")) }
    #expect(await eventually { panel.kindle.state == .reading(done: 0, total: 0) })

    await panel.library.activate(.usb(oasis))
    #expect(await eventually { panel.kindle.volume == oasis })
    await gate.fire()
    await sending.value
    await panel.queue.waitUntilFinished()

    #expect(panel.duplicateReview == nil)
    #expect(channel.deliveries.isEmpty)
    #expect(panel.queue.isEmpty)
    #expect(panel.notice == ProblemPresenter.kindleChangedWhileChecking(.fixture()))
  }

  @Test func switchingTheKindleWhileTheSheetShowsSendsNothing() async {
    let (panel, _, channel) = await twoKindlePanel(first: [sendlesPDF], second: [])
    await panel.quickSend(BookID(rawValue: "a"))
    #expect(panel.duplicateReview != nil)

    await panel.library.activate(.usb(oasis))
    panel.chooseDefault()

    #expect(panel.duplicateReview == nil)
    await panel.waitUntilReviewed()
    await panel.queue.waitUntilFinished()
    #expect(panel.checkingKindle == nil)
    #expect(channel.deliveries.isEmpty)
    #expect(panel.queue.isEmpty)
    #expect(panel.notice == ProblemPresenter.kindleChangedWhileChecking(.fixture()))
  }

  @Test func theSendBarSaysWhileTheKindleIsChecked() async {
    let (panel, kindle, _) = await harness.pluggedInPanel(listing: [])
    let gate = Signal()
    kindle.gate = gate
    let sending = Task { await panel.quickSend(BookID(rawValue: "b")) }

    #expect(await eventually { panel.sendBarHint == "Checking Kindle for duplicates…" })
    await gate.fire()
    await sending.value
    #expect(panel.sendBarHint != "Checking Kindle for duplicates…")
  }
}
