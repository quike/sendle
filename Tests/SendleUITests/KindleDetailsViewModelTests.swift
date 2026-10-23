import Foundation
import SendleDomain
import SendleTestSupport
import SendleUI
import Testing

@MainActor struct KindleDetailsViewModelTests {
  func model(_ book: KindleBook, library: KindleDetailsViewModel.LibraryLink? = nil)
    -> KindleDetailsViewModel
  {
    KindleDetailsViewModel(book: book, library: library, zone: .gmt)
  }

  @Test func aSendleAZW3ShowsItsFacts() {
    let book = KindleBook.fixture(
      path: "El jardin - Lucia.azw3", title: "El jardín", authors: ["Lucía"], source: .sendle,
      asin: "SNOQSFAIKY", documentType: "EBOK", language: "es", year: "2020", byteCount: 52_563,
      modified: Date(timeIntervalSince1970: 1_792_584_000))

    let details = model(book)

    #expect(
      details.facts == ["AZW3", "\(Formatting.size(52_563)) · copied 21 Oct 2026", "From Sendle"])
    #expect(details.title == "El jardín")
    #expect(details.author == "Lucía")
    #expect(details.language == "Spanish")
    #expect(details.year == "2020")
    #expect(details.asin == "SNOQSFAIKY · Book")
    #expect(details.file == "documents/El jardin - Lucia.azw3")
    #expect(details.note == nil)
  }

  @Test func missingDetailsAreNil() {
    let details = model(.fixture(isbn: "", publisher: nil, language: " ", year: "\n"))

    #expect(details.isbn == nil)
    #expect(details.publisher == nil)
    #expect(details.language == nil)
    #expect(details.year == nil)
    #expect(details.asin == nil)
  }

  @Test func aBookWithoutAuthorsHasNoAuthor() {
    #expect(model(.fixture(authors: [])).author == nil)
  }

  @Test func theAuthorReadsAsTheListsShowIt() {
    #expect(model(.fixture(authors: ["Melville, Herman"])).author == "Herman Melville")
  }

  @Test(
    arguments: [
      ("EBOK", "SNOQSFAIKY · Book"), ("PDOC", "SNOQSFAIKY · Personal document"),
      ("XYZ", "SNOQSFAIKY · XYZ"),
    ])
  func theDocumentTypeIsNamed(type: String, expected: String) {
    #expect(model(.fixture(asin: "SNOQSFAIKY", documentType: type)).asin == expected)
  }

  @Test func anASINOrATypeAloneIsShownAlone() {
    #expect(model(.fixture(asin: "SNOQSFAIKY")).asin == "SNOQSFAIKY")
    #expect(model(.fixture(asin: "  ", documentType: "PDOC")).asin == "Personal document")
  }

  @Test func aKFXSaysItsDetailsComeFromItsName() {
    let details = model(.fixture(path: "The Hobbit_B007978NPG.kfx", isProtected: true))

    #expect(
      details.note
        == "Sendle can't read inside KFX files, so these details come from the file name."
    )
  }

  @Test func aTextFileSaysSoToo() {
    let details = model(.fixture(path: "notes.txt"))

    #expect(details.note == "A text file holds no details, so these come from its file name.")
  }

  @Test func aProtectedAZWSaysItIsProtected() {
    #expect(model(.fixture(isProtected: true)).note == "Protected by DRM.")
  }

  @Test func theLibraryLineSaysHowSureTheMatchIs() {
    let id = BookID(rawValue: "A1")
    let sure = KindleDetailsViewModel.LibraryLink(
      id: id, title: "Moby-Dick", isSure: true, canEdit: true)
    let maybe = KindleDetailsViewModel.LibraryLink(
      id: id, title: "Moby-Dick", isSure: false, canEdit: true)

    #expect(model(.fixture(), library: sure).libraryLine == #"In your library as "Moby-Dick""#)
    #expect(
      model(.fixture(), library: maybe).libraryLine == #"Maybe in your library as "Moby-Dick""#)
    #expect(model(.fixture()).libraryLine == nil)
  }

  @Test func theDeleteQuestionSaysWhatGoes() {
    let sideloaded = model(.fixture(path: "Alice.azw3", title: "Alice"))
    let download = model(
      .fixture(path: "Downloads/Items01/The Hobbit_B007978NPG.kfx", title: "The Hobbit"))

    #expect(sideloaded.deleteQuestion == #"Delete "Alice" from this Kindle?"#)
    #expect(sideloaded.deleteDetail == "Its reading position, bookmarks and highlights go too.")
    #expect(
      download.deleteDetail == "Only the download goes; the book stays in your Amazon library.")
  }
}
