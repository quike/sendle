import AppKit
import Foundation
import SendleDomain
import SendleTestSupport
import SendleUI
import Testing

@MainActor @Suite(.timeLimit(.minutes(1)))
struct PanelDetailsTests {
  let harness = PanelHarness()
  let a = BookID(rawValue: "a")
  let b = BookID(rawValue: "b")
  let commandI = KeyInput(.character("i"), command: true)

  private func launched(
    editions: [BookID: Edition] = [:], editFailure: MetadataEditError? = nil
  ) async -> PanelModel {
    let (panel, _) = harness.makePanel(editions: editions, editFailure: editFailure)
    await panel.launch()
    return panel
  }

  private func title(of id: BookID, in panel: PanelModel) -> String? {
    panel.library.books.first { $0.id == id }?.title
  }

  @Test func commandIOpensTheSheetForTheOneSelectedBook() async {
    let panel = await launched()
    panel.click(a, .plain)

    #expect(panel.handle(commandI))
    #expect(await eventually { panel.bookDetails?.book.id == a })
    #expect(harness.system.endedEditing > 0)
  }

  @Test func theSheetShowsTheFilesYearAndTheLatestSend() async throws {
    try await harness.history.append(
      SendRecord(bookID: a, destination: .email, date: Date(), outcome: .sent))
    let panel = await launched(editions: [a: Edition(isbn: "9780000000002", year: "1851")])

    await panel.openDetails(a)

    let details = try #require(panel.bookDetails)
    #expect(details.year == "1851")
    #expect(details.isbn == "9780000000002")
    #expect(details.facts.last?.hasPrefix("Sent by email") == true)
  }

  @Test func commandIDoesNothingWithNoneOrSeveralSelected() async {
    let panel = await launched()
    #expect(!panel.handle(commandI))

    panel.library.selectAll()
    #expect(!panel.handle(commandI))
    await Task.yield()

    #expect(panel.bookDetails == nil)
  }

  @Test func escapeClosesWithoutSaving() async {
    let panel = await launched()
    await panel.openDetails(a)
    panel.bookDetails?.title = "Typee"

    #expect(panel.handle(KeyInput(.escape, isEditingText: true)))

    #expect(panel.bookDetails == nil)
    await panel.library.reload()
    #expect(title(of: a, in: panel) == "Moby-Dick")
    #expect(harness.system.closedPanel == 0)
  }

  @Test func returnSaves() async throws {
    let panel = await launched()
    await panel.openDetails(a)
    let details = try #require(panel.bookDetails)
    details.title = "Typee"

    #expect(panel.handle(KeyInput(.returnKey, isEditingText: true, isRepeat: true)))
    await panel.library.reload()
    #expect(panel.bookDetails === details)
    #expect(title(of: a, in: panel) == "Moby-Dick")

    #expect(panel.handle(KeyInput(.returnKey, isEditingText: true)))
    #expect(await eventually { panel.bookDetails == nil && title(of: a, in: panel) == "Typee" })
  }

  @Test func returnWaitsForADraftThatCanBeSaved() async throws {
    let panel = await launched()
    await panel.openDetails(a)
    let details = try #require(panel.bookDetails)
    details.title = " "

    #expect(panel.handle(KeyInput(.returnKey)))
    await panel.library.reload()

    #expect(panel.bookDetails === details)
    #expect(details.errorText == nil)
  }

  @Test func otherCommandsWaitWhileTheSheetShows() async {
    let panel = await launched()
    panel.click(a, .plain)
    await panel.openDetails(a)
    let layout = panel.library.layout

    let keys = [
      KeyInput(.character(","), command: true), KeyInput(.character("2"), command: true),
      KeyInput(.character("3"), command: true), KeyInput(.down),
      KeyInput(.character("a"), command: true), KeyInput(.character("f"), command: true),
      KeyInput(.character("r"), command: true), commandI,
    ]
    for key in keys { #expect(!panel.handle(key)) }
    await Task.yield()

    #expect(!panel.isShowingSettings)
    #expect(panel.library.layout == layout)
    #expect(panel.library.selection.count == 1)
    #expect(panel.searchFocusRequests == 0)
    #expect(panel.bookDetails?.book.id == a)
  }

  @Test func savingReloadsTheLibraryAndClosesTheSheet() async throws {
    let panel = await launched()
    await panel.openDetails(a)
    try #require(panel.bookDetails).title = "Typee"

    await panel.saveDetails()

    #expect(panel.bookDetails == nil)
    #expect(title(of: a, in: panel) == "Typee")
    #expect(panel.library.items.first { $0.id == a }?.isEdited == true)
    #expect(title(of: b, in: panel) == "Moby-Dick")
  }

  @Test func aFailedSaveKeepsTheSheetWithTheError() async throws {
    let panel = await launched(editFailure: .storage(.writeFailed("disk full")))
    await panel.openDetails(a)
    let details = try #require(panel.bookDetails)
    details.title = "Typee"

    await panel.saveDetails()

    #expect(panel.bookDetails === details)
    #expect(details.errorText == "Couldn't save the details: disk full")
  }

  @Test func storeAndProtectedBooksCantBeEdited() async {
    harness.library.result = .success([
      .fixture(id: "a", isStorePurchase: true), .fixture(id: "b", availability: .protected),
      .fixture(id: "c"),
    ])
    let panel = await launched()
    let editable = Dictionary(
      uniqueKeysWithValues: panel.library.books.map { ($0.id.rawValue, panel.canEditDetails($0)) })
    #expect(editable == ["a": false, "b": false, "c": true])

    await panel.openDetails(a)
    #expect(panel.bookDetails == nil)
    panel.click(b, .plain)
    #expect(!panel.handle(commandI))
    #expect(panel.bookDetails == nil)

    await panel.openDetails(BookID(rawValue: "c"))
    #expect(panel.bookDetails != nil)
  }

  @Test func droppingANonImageShowsTheError() async throws {
    let folder = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let notes = folder.appending(path: "notes.txt")
    try Data("Call me Ishmael.".utf8).write(to: notes)
    let empty = folder.appending(path: "empty.png")
    try Data().write(to: empty)
    let panel = await launched()
    await panel.openDetails(a)
    let details = try #require(panel.bookDetails)

    #expect(await panel.dropCover(notes) == false)
    #expect(details.errorText == "Sendle can't read that image. Choose another one.")
    #expect(await panel.dropCover(empty) == false)
    #expect(await panel.dropCover(folder.appending(path: "gone.png")) == false)
    // Only files are read: a URL from a browser could be fetched.
    let inline = try #require(
      URL(string: "data:image/png;base64,\(try png().base64EncodedString())"))
    #expect(await panel.dropCover(inline) == false)
    #expect(details.coverPreview == nil)
    #expect(!details.isCoverEdited)

    let cover = folder.appending(path: "cover.png")
    try png().write(to: cover)
    #expect(await panel.dropCover(cover))
    #expect(details.coverPreview != nil)
    #expect(details.errorText == nil)
  }

  @Test func choosingAnImageMakesItTheCover() async throws {
    let folder = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let cover = folder.appending(path: "cover.png")
    try png().write(to: cover)
    let panel = await launched()
    await panel.openDetails(a)
    let details = try #require(panel.bookDetails)

    await panel.chooseCoverImage()
    #expect(details.coverPreview == nil)

    harness.system.image = cover
    await panel.chooseCoverImage()
    #expect(details.coverPreview == (try Data(contentsOf: cover)))
  }

  @Test func aPDFsCoverStaysItsFirstPage() async throws {
    harness.library.result = .success([.fixture(id: "a", format: .pdf)])
    let folder = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let cover = folder.appending(path: "cover.png")
    try png().write(to: cover)
    harness.system.image = cover
    let panel = await launched()
    await panel.openDetails(a)
    let details = try #require(panel.bookDetails)

    await panel.chooseCoverImage()
    #expect(await panel.dropCover(cover) == false)

    #expect(details.coverPreview == nil)
  }

  private func png() throws -> Data {
    struct Failure: Error {}
    let image = NSImage(size: NSSize(width: 2, height: 3), flipped: false) { rect in
      NSColor.systemOrange.setFill()
      rect.fill()
      return true
    }
    guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
      let data = bitmap.representation(using: .png, properties: [:])
    else { throw Failure() }
    return data
  }
}
