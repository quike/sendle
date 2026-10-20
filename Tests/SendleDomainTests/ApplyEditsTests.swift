import Foundation
import SendleDomain
import SendleTestSupport
import Testing

@Suite(.timeLimit(.minutes(1)))
struct ApplyEditsTests {
  private let folder = URL(filePath: "/Edits/edit-covers")
  private let early = Date(timeIntervalSince1970: 1_000)
  private let middle = Date(timeIntervalSince1970: 2_000)
  private let late = Date(timeIntervalSince1970: 3_000)

  private func apply(
    _ edits: MetadataEdits, to book: Book, _ authorSort: AuthorSort = .surname
  ) -> Book {
    edits.apply(to: book, authorSort: authorSort, coverFolder: folder)
  }

  @Test func bookEditsWinOverWriterRenamesWhichWinOverBooks() {
    let book = Book.fixture(
      id: "b", title: "Los ritos del agua", author: "Eva Garcia Saenz", language: "es",
      sortAuthor: "Saenz, Eva Garcia")
    var edits = MetadataEdits.none
    edits.writers[WriterKey(author: "Eva Garcia Saenz")!] = WriterEdit(name: "Eva García Sáenz")
    let renamed = apply(edits, to: book)
    #expect(renamed.author == "Eva García Sáenz")
    #expect(renamed.original.author == "Eva Garcia Saenz")
    #expect(renamed.edits.fields == [.writerName])
    edits.books[book.id] = BookEdit(author: "E. G. Sáenz")
    let edited = apply(edits, to: book)
    #expect(edited.author == "E. G. Sáenz")
    #expect(edited.edits.fields == [.author])
  }

  @Test func aWriterRenameReachesEveryBookWithThatBooksAuthorWhateverItsSpelling() {
    var edits = MetadataEdits.none
    edits.writers[WriterKey(author: "Doe, John")!] = WriterEdit(name: "John Q. Doe")
    #expect(apply(edits, to: .fixture(author: "John Doe")).author == "John Q. Doe")
    #expect(apply(edits, to: .fixture(author: "Jane Roe")).author == "Jane Roe")
    #expect(apply(edits, to: .fixture(author: nil)).author == nil)
  }

  @Test func titleLanguageYearAndIsbnComeFromTheBooksEdit() {
    let book = Book.fixture(title: "Moby-Dick", language: "en")
    var edits = MetadataEdits.none
    edits.books[book.id] = BookEdit(
      title: "Moby Dick", year: "1851", isbn: "9780142437247", language: "es")
    let edited = apply(edits, to: book)
    #expect(edited.title == "Moby Dick")
    #expect(edited.language == "es")
    #expect(edited.edits.year == "1851")
    #expect(edited.edits.isbn == "9780142437247")
    #expect(edited.edits.fields == [.title, .year, .isbn, .language])
    #expect(edited.edits.isEdited)
    #expect(edited.original.title == "Moby-Dick")
    #expect(edited.original.language == "en")
  }

  @Test func sortAuthorFollowsWriterThenBooksThenDerivedThenTheSetting() {
    let book = Book.fixture(author: "Eva Garcia Saenz", sortAuthor: "Saenz, Eva Garcia")
    var edits = MetadataEdits.none
    #expect(apply(edits, to: book).sortAuthor == "Saenz, Eva Garcia")
    edits.books[book.id] = BookEdit(author: "Eva García Sáenz")
    #expect(apply(edits, to: book).sortAuthor == "Sáenz, Eva García")
    edits.writers[WriterKey(author: "Eva García Sáenz")!] = WriterEdit(
      sortName: "García Sáenz, Eva")
    #expect(apply(edits, to: book).sortAuthor == "García Sáenz, Eva")
    #expect(apply(edits, to: book, .firstName).sortAuthor == "Eva García Sáenz")
  }

  @Test func aWriterRenameDerivesTheSortAuthorUnlessTheWriterHasASortName() {
    let book = Book.fixture(author: "Eva Garcia Saenz", sortAuthor: "Saenz, Eva Garcia")
    var edits = MetadataEdits.none
    edits.writers[WriterKey(author: "Eva Garcia Saenz")!] = WriterEdit(name: "Eva García Sáenz")
    #expect(apply(edits, to: book).sortAuthor == "Sáenz, Eva García")
    #expect(apply(edits, to: book, .firstName).sortAuthor == "Eva García Sáenz")
  }

  @Test func aRenamedAuthorTakesTheSortNameOfTheNewWriterNotTheOldOne() {
    let book = Book.fixture(author: "Eva Garcia Saenz", sortAuthor: "Saenz, Eva Garcia")
    var edits = MetadataEdits.none
    edits.writers[WriterKey(author: "Eva Garcia Saenz")!] = WriterEdit(
      name: "Evita Saenz", sortName: "Old, Eva", nameChangedAt: early, sortNameChangedAt: late)
    #expect(apply(edits, to: book).sortAuthor == "Saenz, Evita")

    edits.writers[WriterKey(author: "Evita Saenz")!] = WriterEdit(
      sortName: "Sáenz, Evita", sortNameChangedAt: late)
    let surname = apply(edits, to: book, .surname)
    #expect(surname.sortAuthor == "Sáenz, Evita")
    #expect(surname.edits.fields == [.writerName, .writerSortName])
    #expect(surname.edits.changedAt == late)

    let firstName = apply(edits, to: book, .firstName)
    #expect(firstName.sortAuthor == "Evita Saenz")
    #expect(firstName.edits.fields == [.writerName])
    #expect(firstName.edits.changedAt == early)
  }

  @Test func aSortNameForTheOriginalWriterStopsApplyingOnceTheBookMovesToAnotherWriter() {
    let book = Book.fixture(id: "b", author: "Eva Garcia Saenz", sortAuthor: "Saenz, Eva Garcia")
    var edits = MetadataEdits.none
    edits.writers[WriterKey(author: "Eva Garcia Saenz")!] = WriterEdit(
      sortName: "Saenz, E.", sortNameChangedAt: late)
    let beforeMoving = apply(edits, to: book)
    #expect(beforeMoving.sortAuthor == "Saenz, E.")
    #expect(beforeMoving.edits.fields == [.writerSortName])

    edits.books[book.id] = BookEdit(author: "Another Writer", changedAt: early)
    let moved = apply(edits, to: book)
    #expect(moved.sortAuthor == "Writer, Another")
    #expect(moved.edits.fields == [.author])
    #expect(moved.edits.changedAt == early)
  }

  @Test func firstNameSortsAnUneditedAuthorAsShown() {
    let book = Book.fixture(author: "J. R. R. Tolkien", sortAuthor: "Tolkien, J. R. R.")
    #expect(apply(.none, to: book, .firstName).sortAuthor == "J. R. R. Tolkien")
    #expect(apply(.none, to: .fixture(author: nil), .firstName).sortAuthor == nil)
  }

  @Test func aSortNameForTheShownWriterIsIgnoredByFirstNameAndMarksThePencilOnlyBySurname() {
    let book = Book.fixture(author: "Herman Melville")
    var edits = MetadataEdits.none
    edits.writers[WriterKey(author: "Herman Melville")!] = WriterEdit(sortName: "Melville, H.")
    #expect(apply(edits, to: book, .surname).edits.fields == [.writerSortName])
    #expect(apply(edits, to: book, .surname).edits.isEdited)
    #expect(apply(edits, to: book, .firstName).edits.fields.isEmpty)
    #expect(!apply(edits, to: book, .firstName).edits.isEdited)
  }

  @Test func sortTitlesAreDerivedForEveryBookInAListedLanguage() {
    let spanish = Book.fixture(title: "El Principito", language: "es", sortTitle: nil)
    #expect(apply(.none, to: spanish).sortTitle == "Principito, El")
    let japanese = Book.fixture(title: "Kokoro", language: "ja", sortTitle: "Kokoro")
    #expect(apply(.none, to: japanese).sortTitle == "Kokoro")
  }

  @Test func theSortTitleIsTheEditThenTheDerivedOneThenBooksWhileTheTitleIsUnedited() {
    let book = Book.fixture(title: "Moby-Dick", language: "en", sortTitle: "Moby Dick, or")
    #expect(apply(.none, to: book).sortTitle == "Moby Dick, or")

    var edits = MetadataEdits.none
    edits.books[book.id] = BookEdit(title: "The Whale")
    #expect(apply(edits, to: book).sortTitle == "Whale, The")
    edits.books[book.id] = BookEdit(title: "Whale")
    #expect(apply(edits, to: book).sortTitle == nil)
    edits.books[book.id] = BookEdit(title: "The Whale", sortTitle: "Leviathan")
    #expect(apply(edits, to: book).sortTitle == "Leviathan")
    #expect(apply(edits, to: book).edits.fields == [.title, .sortTitle])
  }

  @Test func theDerivedSortTitleFollowsTheEditedLanguage() {
    let book = Book.fixture(title: "El Principito", language: "en")
    var edits = MetadataEdits.none
    #expect(apply(edits, to: book).sortTitle == nil)
    edits.books[book.id] = BookEdit(language: "es")
    #expect(apply(edits, to: book).sortTitle == "Principito, El")
  }

  @Test func changedAtCountsOnlyWhatReachesTheFile() {
    let book = Book.fixture(id: "b", author: "Eva Garcia Saenz")
    let original = WriterKey(author: "Eva Garcia Saenz")!
    var edits = MetadataEdits.none
    edits.books[book.id] = BookEdit(year: "2020", changedAt: early)
    #expect(apply(edits, to: book).edits.changedAt == early)

    edits.writers[original] = WriterEdit(
      name: "Eva García Sáenz", sortName: "Sáenz, Eva", nameChangedAt: middle,
      sortNameChangedAt: late)
    // The sort name belongs to the shown author, which the rename changed; both share a key.
    #expect(apply(edits, to: book, .surname).edits.changedAt == late)
    #expect(apply(edits, to: book, .firstName).edits.changedAt == middle)

    edits.books[book.id] = BookEdit(year: "2020", changedAt: Date(timeIntervalSince1970: 4_000))
    #expect(apply(edits, to: book, .surname).edits.changedAt == Date(timeIntervalSince1970: 4_000))
  }

  @Test func aWriterRenameTheBookOverridesDoesNotCount() {
    let book = Book.fixture(id: "b", author: "Eva Garcia Saenz")
    var edits = MetadataEdits.none
    edits.writers[WriterKey(author: "Eva Garcia Saenz")!] = WriterEdit(
      name: "Eva García Sáenz", nameChangedAt: late)
    edits.books[book.id] = BookEdit(author: "E. G. Sáenz", changedAt: early)
    let applied = apply(edits, to: book).edits
    #expect(applied.changedAt == early)
    #expect(applied.fields == [.author])
  }

  @Test func aRevertedBookKeepsItsChangeDateWithoutBeingEdited() {
    let book = Book.fixture(id: "b")
    let edits = MetadataEdits(books: [book.id: BookEdit(changedAt: middle)])
    let applied = apply(edits, to: book)
    #expect(applied.edits.changedAt == middle)
    #expect(!applied.edits.isEdited)
    #expect(applied.edits.fields.isEmpty)
  }

  @Test func coverEditsResolveInsideTheCoverFolder() {
    let book = Book.fixture(id: "b")
    var edits = MetadataEdits.none
    edits.books[book.id] = BookEdit(cover: "b-abc.jpg")
    let applied = apply(edits, to: book).edits
    #expect(applied.cover == folder.appending(path: "b-abc.jpg"))
    #expect(applied.fields == [.cover])
  }

  @Test func editsForUnknownBooksAreIgnored() {
    let book = Book.fixture(id: "b")
    var edits = MetadataEdits.none
    edits.books[BookID(rawValue: "other")] = BookEdit(title: "Other", cover: "other.jpg")
    #expect(apply(edits, to: book) == book)
    #expect(apply(edits, to: book).edits == .none)
  }

  @Test func applyingStartsFromBooksOwnValuesSoItCanBeRepeated() {
    let book = Book.fixture(id: "b", title: "Moby-Dick", author: "Herman Melville")
    var edits = MetadataEdits.none
    edits.books[book.id] = BookEdit(title: "Moby Dick")
    let once = apply(edits, to: book)
    #expect(apply(edits, to: once) == once)
    #expect(apply(.none, to: once) == book)
  }

  @Test func uneditedGivesBackBooksOwnBook() {
    let book = Book.fixture(
      id: "b", title: "Moby-Dick", author: "Herman Melville", language: "en",
      sortTitle: "Moby-Dick", sortAuthor: "Melville, Herman")
    var edits = MetadataEdits.none
    edits.books[book.id] = BookEdit(title: "Moby Dick", author: "H. Melville", cover: "b.jpg")
    let edited = apply(edits, to: book)
    #expect(edited != book)
    #expect(edited.unedited == book)
    #expect(edited.unedited.edits == .none)
  }

  @Test func aBookBuiltFromBooksValuesKeepsThemAsItsOriginal() {
    let book = Book.fixture(
      title: "The Hobbit", author: "J. R. R. Tolkien", language: "en",
      sortTitle: "Hobbit, The", sortAuthor: "Tolkien, J. R. R.")
    #expect(
      book.original
        == BooksDetails(
          title: "The Hobbit", author: "J. R. R. Tolkien", language: "en",
          sortTitle: "Hobbit, The", sortAuthor: "Tolkien, J. R. R."))
    #expect(book.edits == .none)
    #expect(!book.edits.isEdited)
  }

  @Test func theFixtureTakesOriginalValuesAndEditsOfItsOwn() {
    let original = BooksDetails(title: "Books' title", author: "Books Author")
    let edits = AppliedEdits(fields: [.title], year: "1999")
    let book = Book.fixture(title: "Shown title", original: original, edits: edits)
    #expect(book.title == "Shown title")
    #expect(book.original == original)
    #expect(book.edits == edits)
  }
}
