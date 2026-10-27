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
  let commandL = KeyInput(.character("l"), command: true, isEditingText: true)
  private let isbn = "9788408172277"

  private func launched(
    saved: AppSettings = AppSettings(email: .fixture), editions: [BookID: Edition] = [:],
    editFailure: MetadataEditError? = nil, catalogues: [any BookCatalogue] = []
  ) async -> PanelModel {
    let (panel, _) = harness.makePanel(
      saved, editions: editions, editFailure: editFailure, catalogues: catalogues)
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

  @Test func aHeldReturnSendsNothingOnceTheSheetHasSaved() async throws {
    let panel = await launched()
    panel.click(a, .plain)
    await panel.openDetails(a)
    try #require(panel.bookDetails).title = "Typee"

    #expect(panel.handle(KeyInput(.returnKey)))
    #expect(await eventually { panel.bookDetails == nil && title(of: a, in: panel) == "Typee" })
    #expect(!panel.handle(KeyInput(.returnKey, isRepeat: true)))
    try await Task.sleep(for: .milliseconds(50))

    #expect(panel.route == .library)
    #expect(panel.queue.rows.isEmpty)
    #expect(panel.library.selection.contains(a))
  }

  @Test func thePanelStaysOpenWhileTheSheetShows() async throws {
    let panel = await launched()
    #expect(!panel.holdsPanelOpen)

    await panel.openDetails(a)
    #expect(panel.holdsPanelOpen)
    panel.closeDetails()
    #expect(!panel.holdsPanelOpen)

    await panel.openDetails(a)
    try #require(panel.bookDetails).title = "Typee"
    await panel.saveDetails()
    #expect(!panel.holdsPanelOpen)
  }

  @Test func saveWaitsForADraftThatCanBeSavedAndForTheSaveRunning() async throws {
    let panel = await launched()
    #expect(!panel.canSaveDetails)
    await panel.openDetails(a)
    let details = try #require(panel.bookDetails)
    #expect(panel.canSaveDetails)

    details.year = "17"
    #expect(!panel.canSaveDetails)
    await panel.saveDetails()
    #expect(panel.bookDetails === details)
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

  @Test func aDroppedFileIsCheckedAsSavingWouldCheckIt() async throws {
    let folder = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: folder) }
    // AppKit draws an SVG, but saving can't read one.
    let svg = folder.appending(path: "cover.svg")
    try Data(
      #"<svg xmlns="http://www.w3.org/2000/svg" width="2" height="3"><rect width="2" height="3"/></svg>"#
        .utf8
    ).write(to: svg)
    let header: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    let huge = folder.appending(path: "huge.png")
    try Data(header + [UInt8](repeating: 0, count: 20_000_001 - header.count)).write(to: huge)
    let panel = await launched()
    await panel.openDetails(a)
    let details = try #require(panel.bookDetails)

    #expect(await panel.dropCover(svg) == false)
    #expect(details.errorText == "Sendle can't read that image. Choose another one.")
    #expect(await panel.dropCover(huge) == false)
    #expect(details.errorText == "That image is over 20 MB. Choose a smaller one.")
    harness.system.image = huge
    let cover = folder.appending(path: "cover.png")
    try png().write(to: cover)
    #expect(await panel.dropCover(cover))
    await panel.chooseCoverImage()
    #expect(details.errorText == "That image is over 20 MB. Choose a smaller one.")
    #expect(details.coverPreview != nil && details.isCoverEdited)
  }

  @Test func theSheetDrawsASmallCopyOfALargeCover() async throws {
    let folder = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let cover = folder.appending(path: "cover.png")
    try png(width: 1000, height: 1500).write(to: cover)
    let panel = await launched()
    await panel.openDetails(a)
    let details = try #require(panel.bookDetails)

    #expect(await panel.dropCover(cover))

    let preview = try #require(details.coverPreview.flatMap { NSBitmapImageRep(data: $0) })
    #expect(preview.pixelsHigh <= 400 && preview.pixelsWide < preview.pixelsHigh)
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
    let preview = try #require(details.coverPreview.flatMap { NSBitmapImageRep(data: $0) })
    #expect(preview.pixelsWide == 2 && preview.pixelsHigh == 3)
    #expect(details.isCoverEdited)
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

  // MARK: Lookup

  /// The sheet of book `a`, with its ISBN, looking up in `catalogues`.
  private func sheet(
    saved: AppSettings = AppSettings(email: .fixture), catalogues: [any BookCatalogue]
  ) async throws -> (panel: PanelModel, details: BookDetailsViewModel) {
    let panel = await launched(
      saved: saved, editions: [a: Edition(isbn: isbn)], catalogues: catalogues)
    await panel.openDetails(a)
    return (panel, try #require(panel.bookDetails))
  }

  /// Two editions to pick from, found by title alone.
  private func listing() -> FakeCatalogue {
    FakeCatalogue(
      .openLibrary, byTitle: .success([.fixture(), .fixture(title: "Los ritos del agua II")]))
  }

  @Test func commandLInTheSheetStartsALookup() async throws {
    let gate = Signal()
    let catalogue = FakeCatalogue(.openLibrary, gate: gate)
    let (panel, details) = try await sheet(catalogues: [catalogue])

    #expect(panel.handle(commandL))

    #expect(details.progress?.sources == [.openLibrary])
    #expect(await eventually { catalogue.requests == ["isbn:\(isbn)"] })
    await gate.fire()
  }

  @Test func onlyTheEnabledSourcesAreAsked() async throws {
    let openLibrary = FakeCatalogue(.openLibrary)
    let apple = FakeCatalogue(.appleBooks)
    let (panel, details) = try await sheet(
      saved: AppSettings(email: .fixture, lookupSources: [.appleBooks]),
      catalogues: [openLibrary, apple])

    #expect(panel.handle(commandL))

    #expect(details.progress?.sources == [.appleBooks])
    #expect(await eventually { apple.requests.first == "isbn:\(isbn)" })
    #expect(openLibrary.requests.isEmpty)
  }

  @Test func noSourcesNoLookup() async throws {
    let catalogue = FakeCatalogue(.openLibrary)
    let (panel, details) = try await sheet(
      saved: AppSettings(email: .fixture, lookupSources: []), catalogues: [catalogue])

    #expect(!details.canLookUp)
    #expect(panel.handle(commandL))

    #expect(details.progress == nil)
    #expect(catalogue.requests.isEmpty)
  }

  @Test func withoutACatalogueTheSheetCannotLookUp() async throws {
    let (panel, details) = try await sheet(catalogues: [])

    #expect(!details.canLookUp)
    #expect(panel.handle(commandL))
    #expect(details.progress == nil)
  }

  @Test func commandLOutsideTheSheetIsNotUsed() async {
    let panel = await launched(catalogues: [FakeCatalogue(.openLibrary)])
    panel.click(a, .plain)

    #expect(!panel.handle(commandL))
    #expect(panel.bookDetails == nil)
  }

  @Test func escapeLeavesTheEditionListBeforeTheSheet() async throws {
    let panel = await launched(catalogues: [listing()])
    await panel.openDetails(a)
    let details = try #require(panel.bookDetails)
    #expect(panel.handle(commandL))
    #expect(await eventually { details.isPickingEdition })

    #expect(panel.handle(KeyInput(.escape, isEditingText: true)))

    #expect(panel.bookDetails != nil)
    #expect(!details.isPickingEdition)
    #expect(details.progress == nil)

    #expect(panel.handle(KeyInput(.escape, isEditingText: true)))

    #expect(panel.bookDetails == nil)
    #expect(harness.system.closedPanel == 0)
  }

  @Test func returnWhileChoosingAnEditionDoesNothing() async throws {
    let panel = await launched(catalogues: [listing()])
    await panel.openDetails(a)
    let details = try #require(panel.bookDetails)
    details.title = "Typee"
    #expect(panel.handle(commandL))
    #expect(await eventually { details.isPickingEdition })

    #expect(panel.handle(KeyInput(.returnKey, isEditingText: true)))
    await panel.library.reload()

    #expect(panel.bookDetails != nil)
    #expect(details.isPickingEdition)
    #expect(title(of: a, in: panel) == "Moby-Dick")
  }

  @Test func closingTheSheetCancelsItsLookup() async throws {
    let gate = Signal()
    let catalogue = FakeCatalogue(.openLibrary, gate: gate)
    let (panel, details) = try await sheet(catalogues: [catalogue])
    #expect(panel.handle(commandL))
    #expect(await eventually { !catalogue.requests.isEmpty })

    panel.closeDetails()

    #expect(panel.bookDetails == nil)
    #expect(details.progress == nil)
    #expect(await eventually { catalogue.cancelledRequests == ["isbn:\(isbn)"] })
    await gate.fire()
    #expect(details.progress == nil)
  }

  @Test func savingTheSheetCancelsItsLookup() async throws {
    let gate = Signal()
    let catalogue = FakeCatalogue(.openLibrary, gate: gate)
    let (panel, details) = try await sheet(catalogues: [catalogue])
    details.title = "Typee"
    #expect(panel.handle(commandL))
    #expect(await eventually { !catalogue.requests.isEmpty })

    await panel.saveDetails()

    #expect(panel.bookDetails == nil)
    #expect(details.progress == nil)
    #expect(await eventually { catalogue.cancelledRequests == ["isbn:\(isbn)"] })
    await gate.fire()
  }

  private func png(width: Int = 2, height: Int = 3) throws -> Data {
    struct Failure: Error {}
    guard
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)
    else { throw Failure() }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor.systemOrange.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else { throw Failure() }
    return data
  }
}
