import Foundation
import SendleDomain
import SendleTestSupport
import SendleUI
import Testing

@MainActor @Suite(.timeLimit(.minutes(1)))
struct PanelKindleDetailsTests {
  let harness = PanelHarness()
  let a = BookID(rawValue: "a")

  /// Sendle's own PDF of Moby-Dick, the library's book "a".
  let sendlesPDF = KindleBook.fixture(
    path: "Moby-Dick - Herman Melville.pdf", source: .sendle, asin: "SNMOBYDICK",
    asinFollowsFileName: true)

  private func panelOnKindle() async -> PanelModel {
    let (panel, _, _) = await harness.pluggedInPanel(listing: [sendlesPDF])
    _ = await eventually { panel.kindle.matches?.libraryBook(for: sendlesPDF.id) == a }
    panel.showSide(.kindle)
    return panel
  }

  @Test func aKindleBookOpensItsDetails() async {
    let panel = await panelOnKindle()

    panel.openKindleDetails(sendlesPDF.id)

    #expect(panel.kindleDetails?.library?.id == a)
    #expect(panel.kindleDetails?.library?.isSure == true)
    #expect(panel.kindleDetails?.library?.canEdit == true)
  }

  @Test func theLibrarySideOpensNoKindleDetails() async {
    let panel = await panelOnKindle()
    panel.showSide(.library)

    panel.openKindleDetails(sendlesPDF.id)

    #expect(panel.kindleDetails == nil)
  }

  @Test func anUnknownKindleBookOpensNothing() async {
    let panel = await panelOnKindle()

    panel.openKindleDetails(KindleBookID(relativePath: "gone.azw3"))

    #expect(panel.kindleDetails == nil)
  }

  @Test func escapeAndReturnClose() async {
    let panel = await panelOnKindle()

    panel.openKindleDetails(sendlesPDF.id)
    #expect(panel.handle(KeyInput(.escape)))
    #expect(panel.kindleDetails == nil)

    panel.openKindleDetails(sendlesPDF.id)
    #expect(panel.handle(KeyInput(.returnKey)))
    #expect(panel.kindleDetails == nil)
  }

  @Test func otherKeysWaitWhileItShows() async {
    let panel = await panelOnKindle()
    panel.openKindleDetails(sendlesPDF.id)

    #expect(!panel.handle(KeyInput(.character("a"), command: true)))

    #expect(panel.kindleDetails != nil)
  }

  @Test func theFloatingRailHidesBehindIt() async {
    let panel = await panelOnKindle()
    #expect(panel.controls == .floating)
    #expect(panel.showsFloatingRail)

    panel.openKindleDetails(sendlesPDF.id)

    #expect(!panel.showsFloatingRail)
  }

  @Test func unpluggingTheKindleClosesTheSheet() async {
    let panel = await panelOnKindle()
    panel.openKindleDetails(sendlesPDF.id)

    harness.monitor.update([])

    #expect(await eventually { panel.kindleDetails == nil && panel.side == .library })
  }

  @Test func editInLibraryOpensTheLibraryBooksEditor() async {
    let panel = await panelOnKindle()
    panel.openKindleDetails(sendlesPDF.id)

    await panel.editInLibrary()

    #expect(panel.side == .library)
    #expect(panel.kindleDetails == nil)
    #expect(await eventually { panel.bookDetails?.book.id == a })
    #expect(panel.library.letterJump.top == a)
  }
}
