import SendleDomain
import SendleKindleUSB
import SendleTestSupport
import Testing

struct RemovalPlanTests {
  private let uuid = "0231b0ed-1c4e-4f3b-9a6e-2d5c7f1e8a90"

  private func plan(
    _ book: KindleBook, listing: [KindleBook]? = nil, siblings: Set<String>? = nil,
    thumbnailExists: Bool = true
  ) -> RemovalPlan? {
    RemovalPlan.make(
      for: book, listing: listing ?? [book],
      siblings: siblings ?? [book.fileName.lowercased()], thumbnailExists: { _ in thumbnailExists })
  }

  private func coverParts(_ plan: RemovalPlan?) -> [RemovalPlan.Part] {
    (plan?.parts ?? []).filter {
      switch $0 {
      case .thumbnail, .thumbnailAppleDouble: true
      default: false
      }
    }
  }

  @Test func holdsTheBookThenItsTracesThenItsCover() {
    let book = KindleBook.fixture(
      path: "Abreu, Andrea/Panza.azw3", asin: uuid, documentType: "EBOK")
    let plan = plan(book)
    #expect(
      plan?.parts == [
        .book("documents/Abreu, Andrea/Panza.azw3"),
        .appleDouble("documents/Abreu, Andrea/._Panza.azw3"),
        .sidecar("documents/Abreu, Andrea/Panza.sdr"),
        .thumbnail("system/thumbnails/thumbnail_\(uuid)_EBOK_portrait.jpg"),
        .thumbnailAppleDouble("system/thumbnails/._thumbnail_\(uuid)_EBOK_portrait.jpg"),
      ])
    #expect(plan?.emptyFolders == ["documents/Abreu, Andrea"])
  }

  @Test func exposesThePathOfEveryPart() {
    #expect(RemovalPlan.Part.book("a").path == "a")
    #expect(RemovalPlan.Part.appleDouble("b").path == "b")
    #expect(RemovalPlan.Part.sidecar("c").path == "c")
    #expect(RemovalPlan.Part.thumbnail("d").path == "d")
    #expect(RemovalPlan.Part.thumbnailAppleDouble("e").path == "e")
  }

  @Test func keepsAThumbnailAnotherBookUses() {
    let a = KindleBook.fixture(path: "a.azw3", asin: "EBOK000000", documentType: "EBOK")
    let b = KindleBook.fixture(path: "b.azw3", asin: "EBOK000000", documentType: "EBOK")
    #expect(coverParts(plan(a, listing: [a, b])) == [])
  }

  @Test func keepsAThumbnailOfAnotherTypeOfTheSameASINApart() {
    let a = KindleBook.fixture(path: "a.azw3", asin: "EBOK000000", documentType: "EBOK")
    let b = KindleBook.fixture(path: "b.azw3", asin: "EBOK000000", documentType: "PDOC")
    #expect(
      coverParts(plan(a, listing: [a, b]))
        == [
          .thumbnail("system/thumbnails/thumbnail_EBOK000000_EBOK_portrait.jpg"),
          .thumbnailAppleDouble("system/thumbnails/._thumbnail_EBOK000000_EBOK_portrait.jpg"),
        ])
  }

  @Test func keepsASidecarAnotherFormatShares() {
    let pdf = KindleBook.fixture(path: "Dracula - Bram Stoker.pdf")
    let shared = plan(pdf, siblings: ["dracula - bram stoker.pdf", "dracula - bram stoker.azw3"])
    #expect(!(shared?.parts.contains(.sidecar("documents/Dracula - Bram Stoker.sdr")) ?? true))
    let alone = plan(pdf, siblings: ["dracula - bram stoker.pdf", "dracula - bram stoker.jpg"])
    #expect(alone?.parts.contains(.sidecar("documents/Dracula - Bram Stoker.sdr")) == true)
  }

  @Test func matchesASiblingFormatWithoutRegardToCase() {
    let pdf = KindleBook.fixture(path: "Dracula.PDF")
    let shared = plan(pdf, siblings: ["dracula.pdf", "dracula.mobi"])
    #expect(shared?.parts.contains(.sidecar("documents/Dracula.sdr")) == false)
  }

  @Test func neverEmptiesTheKindlesOwnFolders() {
    let hobbit = KindleBook.fixture(path: "Downloads/Items01/The Hobbit_B007978NPG.kfx")
    let held = plan(hobbit)
    #expect(held?.emptyFolders == [])
    #expect(
      held?.parts.contains(.sidecar("documents/Downloads/Items01/The Hobbit_B007978NPG.sdr"))
        == true)
    #expect(plan(.fixture(path: "Top.pdf"))?.emptyFolders == [])
  }

  @Test func emptiesNestedFoldersDeepestFirst() {
    #expect(
      plan(.fixture(path: "A/B/x.pdf"))?.emptyFolders == ["documents/A/B", "documents/A"])
  }

  @Test func emptiesFoldersBelowDownloadsButNotDownloadsItself() {
    #expect(
      plan(.fixture(path: "Downloads/Items01/Series/x.kfx"))?.emptyFolders
        == ["documents/Downloads/Items01/Series"])
  }

  @Test func knowsTheKindlesOwnFoldersInAnyCase() {
    #expect(plan(.fixture(path: "downloads/Items01/x.kfx"))?.emptyFolders == [])
    #expect(
      plan(.fixture(path: "DOWNLOADS/items01/Series/x.kfx"))?.emptyFolders
        == ["documents/DOWNLOADS/items01/Series"])
  }

  @Test func readsTheSiblingNamesWithoutRegardToCase() {
    let pdf = KindleBook.fixture(path: "Dracula.pdf")
    let shared = plan(pdf, siblings: ["Dracula.pdf", "DRACULA.AZW3"])
    #expect(shared?.parts.contains(.sidecar("documents/Dracula.sdr")) == false)
  }

  @Test(arguments: ["", "../../x", "B0/X", "..", "B0\u{0}X"])
  func noThumbnailForAnASINOrTypeThatIsntAName(value: String) {
    let asin = KindleBook.fixture(path: "a.azw3", asin: value, documentType: "EBOK")
    let type = KindleBook.fixture(path: "b.azw3", asin: "SN5T2DYX77", documentType: value)
    #expect(coverParts(plan(asin)) == [])
    #expect(coverParts(plan(type)) == [])
  }

  @Test func takesTheCoverFromTheListedCopyOfTheBook() {
    let listed = KindleBook.fixture(path: "a.azw3", asin: "SNLISTED01", documentType: "EBOK")
    let stale = KindleBook.fixture(path: "a.azw3", asin: "SNSTALE001", documentType: "PDOC")
    #expect(
      coverParts(plan(stale, listing: [listed]))
        == [
          .thumbnail("system/thumbnails/thumbnail_SNLISTED01_EBOK_portrait.jpg"),
          .thumbnailAppleDouble("system/thumbnails/._thumbnail_SNLISTED01_EBOK_portrait.jpg"),
        ])
  }

  /// FAT matches file names without regard to case, so both books show the one thumbnail.
  @Test func keepsAThumbnailAnotherBookUsesInAnotherCase() {
    let a = KindleBook.fixture(path: "a.azw3", asin: uuid, documentType: "EBOK")
    let b = KindleBook.fixture(path: "b.azw3", asin: uuid.uppercased(), documentType: "ebok")
    #expect(coverParts(plan(a, listing: [a, b])) == [])
  }

  @Test(arguments: [
    "../system/x.azw3", "/x.azw3", "A/../../x.azw3", "", "Downloads/Items01", "A/./x.azw3",
    "A//x.azw3", "README", "A/",
  ])
  func refusesAPathThatIsntABookUnderDocuments(path: String) {
    #expect(plan(.fixture(path: path)) == nil)
  }

  @Test func refusesABookNotInTheListing() {
    let book = KindleBook.fixture(path: "a.azw3")
    #expect(plan(book, listing: [.fixture(path: "b.azw3")]) == nil)
  }

  @Test func noThumbnailWithoutAnASINOrAFile() {
    #expect(coverParts(plan(.fixture(path: "a.pdf"))) == [])
    let azw3 = KindleBook.fixture(path: "b.azw3", asin: uuid, documentType: "EBOK")
    #expect(coverParts(plan(azw3, thumbnailExists: false)) == [])
  }

  @Test func asksForTheThumbnailByItsPathFromTheKindlesRoot() {
    let book = KindleBook.fixture(path: "a.azw3", asin: "SN5T2DYX77", documentType: "EBOK")
    var asked: [String] = []
    _ = RemovalPlan.make(
      for: book, listing: [book], siblings: ["a.azw3"],
      thumbnailExists: {
        asked.append($0)
        return true
      })
    #expect(asked == ["system/thumbnails/thumbnail_SN5T2DYX77_EBOK_portrait.jpg"])
  }
}
