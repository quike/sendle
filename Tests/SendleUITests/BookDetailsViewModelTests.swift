import Foundation
import SendleDomain
import SendleTestSupport
import SendleUI
import Testing

/// Records the drafts the sheet saves, failing with `failure` when set.
@MainActor
private final class SavedDrafts {
  var drafts: [BookDetailsDraft] = []
  var failure: EditDetailsError?

  func save(_ draft: BookDetailsDraft) throws(EditDetailsError) {
    drafts.append(draft)
    if let failure { throw failure }
  }
}

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct BookDetailsViewModelTests {
  private typealias Field = BookDetailsViewModel.Field

  private let now = Date(timeIntervalSince1970: 1_800_000_000)
  private let utc = TimeZone(identifier: "UTC")!
  private let folder = URL(filePath: "/edit-covers", directoryHint: .isDirectory)
  private let fileValues = Edition(isbn: "9780142437247", year: "2016")
  private let eva = Book.fixture(
    id: "eva", title: "Los ritos del agua", author: "Eva Garcia Saenz", language: "es",
    sizeBytes: 1_200_000, sortAuthor: "Saenz, Eva Garcia")
  private var evasKey: WriterKey { WriterKey(author: "Eva Garcia Saenz")! }
  /// Eva's book and two others by her, spelled differently.
  private var library: [Book] {
    [
      eva, .fixture(id: "b", author: "Eva García Sáenz"),
      .fixture(id: "c", author: "Saenz, Eva Garcia"), .fixture(id: "d"),
    ]
  }

  private func shown(
    _ book: Book, with edits: MetadataEdits, _ authorSort: AuthorSort = .surname
  ) -> Book {
    edits.apply(to: book, authorSort: authorSort, coverFolder: folder)
  }

  private func sheet(
    _ book: Book? = nil, library: [Book]? = nil, fileValues: Edition? = nil,
    authorSort: AuthorSort = .surname, lastSend: SendRecord? = nil,
    saved: SavedDrafts = SavedDrafts()
  ) -> BookDetailsViewModel {
    BookDetailsViewModel(
      book: book ?? shown(eva, with: MetadataEdits.none, authorSort),
      library: library ?? self.library, fileValues: fileValues,
      authorSort: authorSort, lastSend: lastSend, now: now, zone: utc,
      save: { (draft: BookDetailsDraft) async throws(EditDetailsError) in
        try saved.save(draft)
      })
  }

  /// A valid ISBN-13 from its first twelve digits, since the mockup's ISBN is made up.
  private func isbn13(_ firstTwelve: String) -> String {
    let digits = firstTwelve.compactMap(\.wholeNumberValue)
    let sum = digits.enumerated().reduce(0) { $0 + $1.element * ($1.offset % 2 == 0 ? 1 : 3) }
    return firstTwelve + String((10 - sum % 10) % 10)
  }

  @Test func startsWithTheShownValues() async {
    let book = shown(eva, with: MetadataEdits(books: [eva.id: BookEdit(year: "2017")]))
    let sent = SendRecord(
      bookID: eva.id, destination: .email, date: now.addingTimeInterval(-3 * 86_400),
      outcome: .sent)
    let saved = SavedDrafts()
    let sheet = sheet(book, fileValues: fileValues, lastSend: sent, saved: saved)

    #expect(sheet.title == "Los ritos del agua")
    #expect(sheet.author == "Eva Garcia Saenz")
    #expect(sheet.sortTitle == "ritos del agua, Los")
    #expect(sheet.sortName == "Saenz, Eva Garcia")
    #expect(sheet.year == "2017")
    #expect(sheet.isbn == "9780142437247")
    #expect(sheet.language == "es")
    #expect(sheet.changesWriter)
    #expect(sheet.coverPreview == nil && sheet.errorText == nil && !sheet.isCoverEdited)
    #expect(Field.allCases.filter(sheet.isEdited) == [.year])
    #expect(sheet.showsSortTitle)
    #expect(sheet.facts == ["EPUB", "1.2 MB · added 14 Nov 2023", "Sent by email · 3d ago"])

    #expect(await sheet.save())
    #expect(
      saved.drafts == [BookDetailsDraft(showing: book, fileValues: fileValues, otherBooks: 2)])

    #expect(self.sheet().facts.last == "Not sent yet")
    let maybe = SendRecord(
      bookID: eva.id, destination: .usb, date: now.addingTimeInterval(-7_200),
      outcome: .unconfirmed)
    #expect(self.sheet(lastSend: maybe).facts.last == "May have been sent over USB · 2h ago")
    #expect(self.sheet(.fixture(sizeBytes: nil)).facts[1] == "Added 14 Nov 2023")
  }

  @Test func editingAFieldMarksItAndRevertRestoresIt() async {
    let sheet = sheet(fileValues: fileValues)
    sheet.title = "Los ritos"
    sheet.author = "Eva García Sáenz"
    sheet.year = "2017"
    sheet.isbn = "978-0-14-243724-7"
    sheet.language = "fr"
    #expect(Field.allCases.filter(sheet.isEdited) == [.title, .author, .year, .isbn, .language])
    #expect(sheet.revertHelp(.title) == "Back to Books: Los ritos del agua")
    #expect(sheet.revertHelp(.author) == "Back to Books: Eva Garcia Saenz")
    #expect(sheet.revertHelp(.year) == "Back to the book's: 2016")
    #expect(sheet.revertHelp(.isbn) == "Back to the book's: 9780142437247")
    #expect(sheet.revertHelp(.language) == "Back to Books: Spanish")

    for field in Field.allCases { sheet.revert(field) }
    #expect(!Field.allCases.contains(where: sheet.isEdited))
    #expect(sheet.title == "Los ritos del agua")
    #expect(sheet.author == "" && sheet.year == "" && sheet.isbn == "" && sheet.language == nil)
    #expect(sheet.placeholder(.author) == "Eva Garcia Saenz")
    #expect(sheet.placeholder(.year) == "2016")
    sheet.year = "2016"
    #expect(!sheet.isEdited(.year))

    // A sort title of the user's own goes back to the one derived from the title.
    sheet.sortTitle = "Agua"
    #expect(sheet.isEdited(.sortTitle))
    sheet.revert(.sortTitle)
    #expect(sheet.sortTitle == "" && !sheet.isEdited(.sortTitle))
    #expect(sheet.placeholder(.sortTitle) == "ritos del agua, Los")

    // The book's own edits open marked, and their reverts are saved cleared.
    let edits = MetadataEdits(books: [
      eva.id: BookEdit(title: "Ritos", sortTitle: "Agua", isbn: "123", language: "fr")
    ])
    let saved = SavedDrafts()
    let edited = self.sheet(shown(eva, with: edits), fileValues: fileValues, saved: saved)
    #expect(Field.allCases.filter(edited.isEdited) == [.title, .sortTitle, .isbn, .language])
    for field in [Field.title, .language, .isbn, .sortTitle] { edited.revert(field) }
    #expect(edited.revertHelp(.sortTitle) == "Back to Books: ritos del agua, Los")
    #expect(await edited.save())
    #expect(
      saved.drafts == [
        BookDetailsDraft(
          title: "Los ritos del agua", author: "Eva Garcia Saenz", sortTitle: "",
          sortName: nil, year: "2016", isbn: "", language: nil, cover: .keep,
          changesWriter: true)
      ])

    // Values the sheet can't know yet are named by what they are.
    let unknown = self.sheet(.fixture(author: nil, language: nil))
    #expect(unknown.revertHelp(.year) == "Back to the book's own year")
    #expect(unknown.revertHelp(.isbn) == "Back to the book's own ISBN")
    #expect(unknown.revertHelp(.author) == "Back to Books: no author")
    #expect(unknown.revertHelp(.language) == "Back to Books: no language")
  }

  @Test func anUntouchedSortLineFollowsTheTitleAndAuthor() async throws {
    let saved = SavedDrafts()
    let sheet = sheet(saved: saved)
    sheet.title = "Los ritos del fuego"
    sheet.author = "Eva García Sáenz"
    #expect(sheet.sortTitle == "ritos del fuego, Los")
    #expect(sheet.sortName == "Sáenz, Eva García")
    #expect(!sheet.isEdited(.sortTitle) && !sheet.isEdited(.sortName))
    // The draft leaves untouched lines out, so saving derives them afresh.
    #expect(await sheet.save())
    let untouched = try #require(saved.drafts.last)
    #expect(untouched.sortTitle == nil && untouched.sortName == nil)

    // A line typed back to the opening sort form is still saved as typed.
    sheet.sortName = "Saenz, Eva Garcia"
    #expect(await sheet.save())
    #expect(try #require(saved.drafts.last).sortName == "Saenz, Eva Garcia")

    let custom = self.sheet(
      shown(eva, with: MetadataEdits(books: [eva.id: BookEdit(sortTitle: "Agua")])))
    custom.title = "Los ritos del fuego"
    #expect(custom.sortTitle == "Agua" && custom.isEdited(.sortTitle))

    let sorted = self.sheet(
      shown(eva, with: MetadataEdits(writers: [evasKey: WriterEdit(sortName: "García, Eva")])))
    #expect(sorted.sortName == "García, Eva" && sorted.isEdited(.sortName))
    sorted.author = "Eva García Sáenz"
    #expect(sorted.sortName == "García, Eva")
    sorted.author = "Eva G."
    #expect(sorted.sortName == "G., Eva" && !sorted.isEdited(.sortName))

    let moby = self.sheet(.fixture())
    #expect(!moby.showsSortTitle)
    moby.title = "The Whale"
    #expect(moby.showsSortTitle && moby.sortTitle == "Whale, The")
    moby.title = "Moby-Dick"
    moby.sortTitle = "Whale"
    #expect(moby.showsSortTitle)
    moby.revert(.sortTitle)
    #expect(!moby.showsSortTitle)
  }

  @Test func writerCheckboxAppearsOnlyWhenTheAuthorChangesAndOtherBooksExist() async {
    let saved = SavedDrafts()
    let sheet = sheet(saved: saved)
    #expect(!sheet.showsWriterCheckbox)
    sheet.author = "Eva García Sáenz"
    #expect(sheet.showsWriterCheckbox)
    #expect(sheet.changesWriter)
    #expect(sheet.writerCheckboxTitle == #"Also change the 2 other books by "Eva Garcia Saenz""#)
    sheet.changesWriter = false
    sheet.author = "Eva Garcia Saenz "
    #expect(!sheet.showsWriterCheckbox)
    // Hidden, the checkbox keeps its default.
    #expect(await sheet.save())
    #expect(saved.drafts.last?.changesWriter == true)

    let alone = self.sheet(library: [eva], saved: saved)
    alone.author = "Eva García Sáenz"
    #expect(!alone.showsWriterCheckbox)
    #expect(await alone.save())
    #expect(saved.drafts.last?.changesWriter == false)

    let pair = self.sheet(library: [eva, .fixture(id: "b", author: "Eva Garcia Saenz")])
    pair.author = "Eva"
    #expect(pair.writerCheckboxTitle == #"Also change the 1 other book by "Eva Garcia Saenz""#)
  }

  @Test func revertingAWriterRenameShowsTheCheckboxTicked() async {
    let renamed = shown(
      eva, with: MetadataEdits(writers: [evasKey: WriterEdit(name: "Eva G. Sáenz")]))
    let saved = SavedDrafts()
    let sheet = sheet(renamed, saved: saved)
    #expect(sheet.author == "Eva G. Sáenz" && sheet.isEdited(.author))
    sheet.author = "Eva G."
    sheet.changesWriter = false
    sheet.revert(.author)
    #expect(sheet.showsWriterCheckbox && sheet.changesWriter)
    #expect(await sheet.save())
    #expect(saved.drafts.last?.author == "" && saved.drafts.last?.changesWriter == true)

    // With no other books the checkbox stays hidden, and the revert still reaches the writer.
    let alone = self.sheet(renamed, library: [renamed], saved: saved)
    alone.revert(.author)
    #expect(!alone.showsWriterCheckbox)
    #expect(await alone.save())
    #expect(saved.drafts.last?.changesWriter == true)
  }

  @Test func writerCheckboxShowsOnlyWhenItHasAnEffect() {
    // Clearing the author of an unedited book changes no other book.
    let unedited = sheet()
    unedited.revert(.author)
    #expect(!unedited.showsWriterCheckbox)

    // A book's own author may override a rename, which the revert can also remove.
    let own = sheet(
      shown(eva, with: MetadataEdits(books: [eva.id: BookEdit(author: "E. G. Sáenz")])))
    own.revert(.author)
    #expect(own.showsWriterCheckbox)

    // Revert all reaches the writer's sort name, so it shows the checkbox, ticked.
    let sortName = MetadataEdits(writers: [evasKey: WriterEdit(sortName: "García, Eva")])
    let sorted = sheet(shown(eva, with: sortName))
    sorted.revert(.author)
    #expect(!sorted.showsWriterCheckbox)
    sorted.changesWriter = false
    sorted.revertAll()
    #expect(sorted.showsWriterCheckbox && sorted.changesWriter)
    let alone = sheet(shown(eva, with: sortName), library: [eva])
    alone.revertAll()
    #expect(!alone.showsWriterCheckbox)
  }

  @Test func revertAllRemovesAWritersSortNameOnlyWithTheBoxTicked() async throws {
    let edits = MetadataEdits(writers: [evasKey: WriterEdit(sortName: "García, Eva")])
    let saved = SavedDrafts()
    let sheet = sheet(shown(eva, with: edits), saved: saved)
    sheet.revertAll()
    #expect(sheet.changesWriter && !sheet.isEdited(.sortName))
    #expect(await sheet.save())
    #expect(saved.drafts.last?.sortName == "")

    sheet.changesWriter = false
    #expect(sheet.isEdited(.sortName) && sheet.sortName == "García, Eva")
    #expect(await sheet.save())
    #expect(try #require(saved.drafts.last).sortName == nil)

    // The line's own ↺ removes it whatever the checkbox says.
    sheet.revert(.sortName)
    #expect(await sheet.save())
    #expect(saved.drafts.last?.sortName == "")
  }

  @Test func revertAllRemovesALoneWritersSortName() async {
    let edits = MetadataEdits(writers: [evasKey: WriterEdit(sortName: "García, Eva")])
    let saved = SavedDrafts()
    let sheet = sheet(shown(eva, with: edits), library: [eva], saved: saved)
    sheet.revertAll()
    #expect(!sheet.showsWriterCheckbox && !sheet.isEdited(.sortName))
    #expect(await sheet.save())
    #expect(saved.drafts.last?.sortName == "")
  }

  @Test func sortNameLineHiddenUnderFirstName() {
    #expect(sheet().showsSortName)
    let firstName = sheet(authorSort: .firstName)
    #expect(!firstName.showsSortName)
    #expect(firstName.sortName == "Eva Garcia Saenz" && !firstName.isEdited(.sortName))
  }

  @Test func isbnStatusTracksValidity() {
    let sheet = sheet()
    let valid = isbn13("978-84-08-17227-")
    sheet.isbn = valid
    #expect(sheet.isbnStatus == .valid)
    sheet.isbn = String(valid.dropLast()) + String(((valid.last?.wholeNumberValue ?? 0) + 1) % 10)
    #expect(sheet.isbnStatus == .invalid)
    sheet.isbn = ""
    #expect(sheet.isbnStatus == .empty)
    sheet.isbn = "123"
    #expect(sheet.isbnStatus == .invalid)
  }

  @Test func cannotSaveWithoutATitleOrWithABadYear() async {
    let saved = SavedDrafts()
    let sheet = sheet(saved: saved)
    #expect(sheet.canSave)
    sheet.title = " "
    #expect(!sheet.canSave)
    #expect(await sheet.save() == false)
    sheet.title = "Ritos"
    for year in ["17", "20177", "2O16", "２０１６"] {
      sheet.year = year
      #expect(!sheet.canSave)
    }
    for year in ["", "2016", " 2016 "] {
      sheet.year = year
      #expect(sheet.canSave)
    }
    #expect(saved.drafts.isEmpty)
  }

  @Test func pdfHidesCoverYearISBNAndLanguage() {
    let pdf = sheet(.fixture(id: "p", format: .pdf))
    #expect(pdf.isPDF && !pdf.canChangeCover)
    pdf.setCover(Data([1]))
    #expect(pdf.coverPreview == nil && !pdf.isCoverEdited)
    #expect(pdf.facts.first == "PDF")

    let epub = sheet()
    #expect(!epub.isPDF && epub.canChangeCover)
    let inCloud = sheet(.fixture(id: "cloud", availability: .inCloudOnly))
    #expect(!inCloud.isPDF && !inCloud.canChangeCover)
  }

  @Test func theCoverShowsTheEditedTitleWithTheChosenCover() {
    let retitled = sheet(shown(eva, with: MetadataEdits(books: [eva.id: BookEdit(title: "Ritos")])))
    #expect(retitled.coverBook.title == "Ritos")
    #expect(retitled.coverBook.edits.cover == nil)

    let covered = sheet(
      shown(eva, with: MetadataEdits(books: [eva.id: BookEdit(title: "Ritos", cover: "eva.jpg")])))
    #expect(covered.coverBook.edits.cover == folder.appending(path: "eva.jpg"))
    covered.revertCover()
    #expect(covered.coverBook.edits.cover == nil)
    #expect(!covered.coverBook.edits.fields.contains(.cover))
    #expect(covered.coverBook.title == "Ritos" && covered.coverBook.id == eva.id)
  }

  @Test func choosingACoverPreviewsItAndRevertPutsTheBooksBack() async {
    let saved = SavedDrafts()
    let sheet = sheet(saved: saved)
    sheet.setCover(Data([1, 2, 3]))
    #expect(sheet.coverPreview == Data([1, 2, 3]) && sheet.isCoverEdited)
    #expect(await sheet.save())
    #expect(saved.drafts.last?.cover == .replace(Data([1, 2, 3])))
    sheet.revertCover()
    #expect(sheet.coverPreview == nil && !sheet.isCoverEdited)

    let covered = self.sheet(
      shown(eva, with: MetadataEdits(books: [eva.id: BookEdit(cover: "eva.jpg")])), saved: saved)
    #expect(covered.isCoverEdited)
    covered.revertCover()
    #expect(!covered.isCoverEdited)
    #expect(await covered.save())
    #expect(saved.drafts.last?.cover == .revert)
  }

  @Test func revertAllResetsEveryFieldAndTheCover() async {
    let edits = MetadataEdits(
      books: [
        eva.id: BookEdit(
          title: "Ritos", author: "E. G. Sáenz", sortTitle: "Agua", year: "1999", isbn: "123",
          language: "fr", cover: "eva.jpg")
      ],
      writers: [WriterKey(author: "E. G. Sáenz")!: WriterEdit(sortName: "Sáenz, E. G.")])
    let saved = SavedDrafts()
    let sheet = sheet(shown(eva, with: edits), fileValues: fileValues, saved: saved)
    #expect(Field.allCases.allSatisfy(sheet.isEdited))
    #expect(sheet.isCoverEdited)
    sheet.setCover(Data([1, 2]))

    sheet.revertAll()
    #expect(!Field.allCases.contains(where: sheet.isEdited))
    #expect(!sheet.isCoverEdited && sheet.coverPreview == nil)
    #expect(await sheet.save())
    #expect(
      saved.drafts == [
        BookDetailsDraft(
          title: "Los ritos del agua", author: "", sortTitle: "", sortName: "", year: "",
          isbn: "", language: nil, cover: .revert, changesWriter: true)
      ])
  }

  @Test func saveFailureKeepsTheSheetWithTheError() async {
    let saved = SavedDrafts()
    saved.failure = .storage("disk full")
    let sheet = sheet(saved: saved)
    sheet.title = "Ritos"
    #expect(await sheet.save() == false)
    #expect(sheet.errorText == "Couldn't save the details: disk full")
    #expect(sheet.title == "Ritos")

    let messages: [(EditDetailsError, String)] = [
      (.invalidYear, "Enter the year as four digits, like 2017."),
      (.invalidLanguage, "Enter a language tag, like es or pt-BR."),
      (.unreadableImage, "Sendle can't read that image. Choose another one."),
      (.imageTooLarge, "That image is over 20 MB. Choose a smaller one."),
    ]
    for (failure, message) in messages {
      saved.failure = failure
      #expect(await sheet.save() == false)
      #expect(sheet.errorText == message)
    }

    saved.failure = nil
    #expect(await sheet.save())
    #expect(sheet.errorText == nil)
  }

  @Test func languagesListAmazonsTags() {
    let sheet = sheet()
    let names = sheet.languages.map { $0.name }
    #expect(sheet.languages.count == 41)
    #expect(sheet.languages.contains { $0.tag == "es" && $0.name == "Spanish" })
    #expect(names == names.sorted())
    #expect(names.first == "Afrikaans")
    #expect(sheet.languageWarning == nil)

    let russian = self.sheet(.fixture(id: "ru", language: "ru"))
    #expect(russian.languages.count == 42)
    #expect(russian.languages.last?.tag == "ru" && russian.languages.last?.name == "Other: ru")
    #expect(russian.languageWarning == "Amazon may not convert this language")

    let american = self.sheet(.fixture(id: "us", language: "en-US"))
    #expect(
      american.languages.contains { $0.tag == "en-US" && $0.name == "English (United States)" })
    #expect(american.languageWarning == nil)

    // A tag spelled another way is listed once, as the book spells it, so the pop-up finds it.
    let shouted = self.sheet(.fixture(id: "es", language: "ES"))
    #expect(shouted.languages.count == 41)
    #expect(shouted.languages.filter { $0.name == "Spanish" }.map { $0.tag } == ["ES"])
    #expect(shouted.languageWarning == nil)

    // A tag typed through "Other…" is listed too.
    sheet.language = "eo"
    #expect(sheet.languages.last?.name == "Other: eo")
    #expect(sheet.languageWarning == "Amazon may not convert this language")
  }

  @Test func theLanguagePopUpChoosesATagOrTypesOne() {
    let sheet = sheet()
    #expect(sheet.languageTitle == "Spanish")
    #expect(sheet.isChosenLanguage("es") && !sheet.isChosenLanguage("en"))

    sheet.chooseLanguage("en")
    #expect(sheet.language == "en" && sheet.languageTitle == "English")
    #expect(sheet.isEdited(.language))

    sheet.typeOtherLanguage()
    #expect(sheet.isTypingLanguage && sheet.languageTitle == "Other…")
    #expect(!sheet.isChosenLanguage("en"))
    sheet.typedLanguage = "eo"
    #expect(sheet.language == "eo")

    sheet.revert(.language)
    #expect(!sheet.isTypingLanguage && sheet.language == nil)
    #expect(sheet.languageTitle == "Spanish" && sheet.isChosenLanguage("es"))

    #expect(self.sheet(.fixture(id: "none", language: nil)).languageTitle == "No language")
  }

  @Test func aSortLineBecomesAFieldAfterEditAndWhileEdited() {
    let sheet = sheet()
    #expect(!sheet.showsSortTitleField && !sheet.showsSortNameField)

    sheet.isEditingSortTitle = true
    sheet.isEditingSortName = true
    #expect(sheet.showsSortTitleField && sheet.showsSortNameField)
    // Basque has no article to move, so the line would hide; a field opened by Edit stays.
    sheet.language = "eu"
    #expect(sheet.showsSortTitle)
    sheet.revertAll()
    #expect(!sheet.showsSortTitleField && !sheet.showsSortNameField)

    let sorted = self.sheet(
      shown(eva, with: MetadataEdits(books: [eva.id: BookEdit(sortTitle: "Agua")])))
    #expect(sorted.showsSortTitleField)
  }

  @Test func aRefusedCoverSaysWhyUntilAnotherIsChosen() {
    let sheet = sheet()
    sheet.refuseCover(.unreadableImage)
    #expect(sheet.errorText == "Sendle can't read that image. Choose another one.")
    #expect(!sheet.isCoverEdited)

    sheet.setCover(Data([1]))
    #expect(sheet.errorText == nil && sheet.isCoverEdited)
  }
}
