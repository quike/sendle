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

    panel.quickSend(BookID(rawValue: "a"))
    await panel.queue.waitUntilFinished()

    #expect(kindle.listings == 2)
  }

  @Test func anEmailSendOnlyMatchesAgain() async {
    let kindle = FakeKindleLibrary(.success(.fixture([emailedCopy])))
    let (panel, _) = harness.makePanel(kindle: kindle)
    harness.monitor.update([.fixture()])
    await panel.launch()
    await panel.panelDidOpen()
    #expect(await eventually { panel.kindle.state == .loaded && panel.kindle.matches != nil })
    #expect(panel.library.kindleMatches?.byBook[BookID(rawValue: "a")] == nil)

    panel.quickSend(BookID(rawValue: "a"))
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

    panel.quickSend(BookID(rawValue: "a"))
    await channel.waitUntilDeliveryStarts()
    #expect(panel.ejectActionName(for: kindle) == nil)

    panel.queue.cancel()
    await panel.queue.waitUntilFinished()
    #expect(panel.ejectActionName(for: kindle) == "Eject Kindle")
  }
}
