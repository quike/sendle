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

  /// The Kindle side, once the first of `listing` is matched to the library's book "a".
  private func panelOnKindle(
    listing: [KindleBook]? = nil, books: [Book]? = nil
  ) async -> PanelModel {
    let listing = listing ?? [sendlesPDF]
    let (panel, _, _) = await harness.pluggedInPanel(listing: listing, books: books)
    #expect(await eventually { panel.kindle.matches?.libraryBook(for: listing[0].id) == a })
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

  @Test func aMaybeMatchIsLinkedAsUnsure() async {
    let byHand = KindleBook.fixture()
    let panel = await panelOnKindle(listing: [byHand])

    panel.openKindleDetails(byHand.id)

    #expect(panel.kindleDetails?.library?.id == a)
    #expect(panel.kindleDetails?.library?.isSure == false)
  }

  @Test func aBookNoLibraryBookMatchesHasNoLink() async {
    let stranger = KindleBook.fixture(
      path: "Typee - Nobody.azw3", title: "Typee", authors: ["Nobody"])
    let panel = await panelOnKindle(listing: [sendlesPDF, stranger])

    panel.openKindleDetails(stranger.id)

    #expect(panel.kindleDetails?.item.book.id == stranger.id)
    #expect(panel.kindleDetails?.library == nil)
  }

  @Test func aBookTheLibraryCannotEditHasNothingToEditThere() async {
    let panel = await panelOnKindle(
      books: [.fixture(id: "a", format: .pdf, isStorePurchase: true)])
    panel.openKindleDetails(sendlesPDF.id)
    #expect(panel.kindleDetails?.library?.canEdit == false)

    await panel.editInLibrary()

    #expect(panel.kindleDetails != nil)
    #expect(panel.side == .kindle)
    #expect(panel.bookDetails == nil)
  }

  @Test func aDuplicateCheckKeepsTheSheetFromOpening() async {
    let (panel, kindle, _) = await harness.pluggedInPanel(listing: [sendlesPDF])
    panel.showSide(.kindle)
    let gate = Signal()
    kindle.gate = gate
    let sending = Task { await panel.quickSend(BookID(rawValue: "b")) }
    #expect(await eventually { panel.checkingKindle != nil })

    panel.openKindleDetails(sendlesPDF.id)

    #expect(panel.kindleDetails == nil)
    await gate.fire()
    await sending.value
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

    #expect(!panel.handle(KeyInput(.character("f"), command: true)))
    #expect(!panel.handle(KeyInput(.character(","), command: true)))
    await Task.yield()

    #expect(panel.searchFocusRequests == 0)
    #expect(!panel.isShowingSettings)
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
