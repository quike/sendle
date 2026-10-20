import Foundation
import SendleDomain
import SendleTestSupport
import Testing

@Suite(.timeLimit(.minutes(1)))
struct EditBookDetailsTests {
  private let folder = URL(filePath: "/edit-covers", directoryHint: .isDirectory)
  private let earlier = Date(timeIntervalSince1970: 1_000)
  private let now = Date(timeIntervalSince1970: 9_000)
  private let fileValues = Edition(isbn: "9780142437247", year: "1851")
  private let eva = Book.fixture(
    id: "eva", title: "Los ritos del agua", author: "Eva Garcia Saenz", language: "es",
    sortAuthor: "Saenz, Eva Garcia")
  private var evasKey: WriterKey { WriterKey(author: "Eva Garcia Saenz")! }

  private func editor(
    _ store: InMemoryMetadataEditStore, _ authorSort: AuthorSort = .surname, at date: Date? = nil
  ) -> EditBookDetails {
    let date = date ?? now
    return EditBookDetails(
      store: store, settings: InMemorySettingsStore(AppSettings(authorSort: authorSort)),
      now: { date })
  }

  private func shown(
    _ book: Book, with edits: MetadataEdits, _ authorSort: AuthorSort = .surname
  ) -> Book {
    edits.apply(to: book, authorSort: authorSort, coverFolder: folder)
  }

  /// Opens the sheet on `book` shown with `edits`, its writer having `otherBooks` other books,
  /// makes `change` and saves; returns the edits.
  private func save(
    _ book: Book, with edits: MetadataEdits = MetadataEdits.none, fileValues: Edition? = nil,
    authorSort: AuthorSort = .surname, otherBooks: Int = 1,
    _ change: (inout BookDetailsDraft) -> Void
  ) async throws(EditDetailsError) -> MetadataEdits {
    let store = InMemoryMetadataEditStore(edits, coverFolder: folder)
    let book = shown(book, with: edits, authorSort)
    var draft = BookDetailsDraft(showing: book, fileValues: fileValues, otherBooks: otherBooks)
    change(&draft)
    try await editor(store, authorSort).save(draft, for: book, fileValues: fileValues)
    return await store.edits()
  }

  // MARK: Book fields

  @Test func theDraftOpensWithTheShownValuesAndTheFilesYearAndISBN() {
    let edits = MetadataEdits(books: [eva.id: BookEdit(isbn: "123")])
    let draft = BookDetailsDraft(
      showing: shown(eva, with: edits), fileValues: fileValues, otherBooks: 2)
    #expect(
      draft
        == BookDetailsDraft(
          title: "Los ritos del agua", author: "Eva Garcia Saenz",
          sortTitle: "ritos del agua, Los", sortName: "Saenz, Eva Garcia", year: "1851",
          isbn: "123", language: "es", cover: .keep, changesWriter: true))
    let unknown = BookDetailsDraft(showing: .fixture(author: nil), fileValues: nil, otherBooks: 0)
    #expect(unknown.author == "" && unknown.sortName == "" && unknown.year == "")
    #expect(unknown.sortTitle == "Moby-Dick")
  }

  @Test func aValueEqualToTheBooksOwnRemovesTheEdit() async throws {
    let book = Book.fixture(id: "b", title: "Moby-Dick", language: "en")
    let edits = MetadataEdits(books: [
      book.id: BookEdit(
        title: "Moby Dick", year: "1999", isbn: "978-0-14-243724-7", language: "es",
        changedAt: earlier)
    ])
    let saved = try await save(book, with: edits, fileValues: fileValues) {
      $0.title = " Moby-Dick "
      $0.year = "1851"
      $0.isbn = "9780142437247"
      $0.language = "EN"
    }
    #expect(saved.books[book.id] == BookEdit(changedAt: now))
  }

  @Test func changedValuesAreStoredTrimmedAndTheISBNAsTyped() async throws {
    let book = Book.fixture(id: "b", title: "Moby-Dick")
    let saved = try await save(book, fileValues: fileValues) {
      $0.title = "  Moby Dick "
      $0.year = " 1852"
      $0.isbn = " 978-84-123 "
    }
    #expect(
      saved.books[book.id]
        == BookEdit(title: "Moby Dick", year: "1852", isbn: "978-84-123", changedAt: now))
  }

  @Test func aClearedFieldRevertsIt() async throws {
    let book = Book.fixture(id: "b", title: "Moby-Dick", author: "Herman Melville")
    let edits = MetadataEdits(books: [
      book.id: BookEdit(
        author: "H. Melville", sortTitle: "Whale", year: "1999", isbn: "123", language: "es")
    ])
    let saved = try await save(book, with: edits, fileValues: fileValues) {
      $0.author = ""
      $0.sortTitle = " "
      $0.year = " "
      $0.isbn = ""
      $0.language = nil
    }
    #expect(saved.books[book.id] == BookEdit(changedAt: now))
    #expect(saved.writers.isEmpty)
  }

  @Test func emptyTitleIsRefused() async {
    let store = InMemoryMetadataEditStore(coverFolder: folder)
    var draft = BookDetailsDraft(showing: eva, fileValues: nil, otherBooks: 0)
    draft.title = " \n"
    draft.year = "2016"
    await #expect(throws: EditDetailsError.emptyTitle) {
      try await editor(store).save(draft, for: eva, fileValues: nil)
    }
    #expect(await store.edits() == MetadataEdits.none)
  }

  @Test func yearMustBeFourDigits() async throws {
    for year in ["17", "20177", "２０１６", "2O16", "-201"] {
      await #expect(throws: EditDetailsError.invalidYear) {
        try await save(eva) { $0.year = year }
      }
    }
    let saved = try await save(eva) { $0.year = "2016" }
    #expect(saved.books[eva.id]?.year == "2016")
    let reverted = try await save(eva, with: saved) { $0.year = "" }
    #expect(reverted.books[eva.id] == BookEdit(changedAt: now))
  }

  @Test func languageMustBeABCP47Tag() async throws {
    for language in ["Spanish", "e", "es-", "es--ES", "español", "es-ABCDEFGHI", "es ES"] {
      await #expect(throws: EditDetailsError.invalidLanguage) {
        try await save(eva) { $0.language = language }
      }
    }
    for (typed, stored) in [("en", "en"), (" pt_BR ", "pt-BR"), ("zh-Hant-TW", "zh-Hant-TW")] {
      let saved = try await save(eva) { $0.language = typed }
      #expect(saved.books[eva.id]?.language == stored)
    }
    let odd = Book.fixture(id: "odd", language: "English")
    let kept = try await save(odd) { $0.title = "Moby Dick" }
    #expect(kept.books[odd.id] == BookEdit(title: "Moby Dick", changedAt: now))
  }

  @Test func untouchedFieldsKeepTheirEdits() async throws {
    let edits = MetadataEdits(books: [
      eva.id: BookEdit(author: "E. G. Sáenz", sortTitle: "Ritos", changedAt: earlier)
    ])
    #expect(try await save(eva, with: edits) { _ in } == edits)
    // The writer checkbox starts ticked, but an author left alone isn't renamed writer-wide.
    let saved = try await save(eva, with: edits) { $0.title = "Los ritos" }
    #expect(saved.writers.isEmpty)
    #expect(
      saved.books[eva.id]
        == BookEdit(title: "Los ritos", author: "E. G. Sáenz", sortTitle: "Ritos", changedAt: now))
  }

  @Test func aSortTitleEqualToTheDerivedOneRemovesIt() async throws {
    let edits = MetadataEdits(books: [eva.id: BookEdit(sortTitle: "Ritos")])
    let derived = try await save(eva, with: edits) { $0.sortTitle = "ritos del agua, Los" }
    #expect(derived.books[eva.id] == BookEdit())
    let retitled = try await save(eva, with: edits) {
      $0.title = "Las aguas"
      $0.sortTitle = "aguas, Las"
    }
    #expect(retitled.books[eva.id] == BookEdit(title: "Las aguas", changedAt: now))
  }

  // MARK: Writer

  @Test func aWriterWideRenameIsStoredUnderBooksAuthorKey() async throws {
    let edits = MetadataEdits(books: [eva.id: BookEdit(author: "E. G. Sáenz")])
    let saved = try await save(eva, with: edits) {
      $0.author = "Eva G. Sáenz"
      $0.changesWriter = true
    }
    #expect(saved.writers == [evasKey: WriterEdit(name: "Eva G. Sáenz", nameChangedAt: now)])
    #expect(saved.books[eva.id] == BookEdit(changedAt: now))
    let another = Book.fixture(id: "another", author: "Saenz, Eva Garcia")
    #expect(shown(another, with: saved).author == "Eva G. Sáenz")
  }

  @Test func aBookOnlyRenameIsStoredOnTheBook() async throws {
    let saved = try await save(eva) {
      $0.author = "Eva G. Sáenz"
      $0.changesWriter = false
    }
    #expect(saved.books[eva.id] == BookEdit(author: "Eva G. Sáenz", changedAt: now))
    #expect(saved.writers.isEmpty)

    // Back to Books' author for this book alone overrides the writer's rename.
    let renamed = MetadataEdits(writers: [evasKey: WriterEdit(name: "Eva G. Sáenz")])
    let alone = try await save(eva, with: renamed) {
      $0.author = "Eva Garcia Saenz"
      $0.changesWriter = false
    }
    #expect(alone.books[eva.id] == BookEdit(author: "Eva Garcia Saenz", changedAt: now))
    #expect(alone.writers == renamed.writers)
  }

  @Test func aWriterWideRevertRemovesTheRenameAndTheBooksOwn() async throws {
    let edits = MetadataEdits(
      books: [eva.id: BookEdit(author: "E. G. Sáenz", changedAt: earlier)],
      writers: [evasKey: WriterEdit(name: "Eva G. Sáenz", nameChangedAt: earlier)])
    let saved = try await save(eva, with: edits) { $0.author = "Eva Garcia Saenz" }
    #expect(saved.books[eva.id] == BookEdit(changedAt: now))
    #expect(saved.writers == [evasKey: WriterEdit(nameChangedAt: now)])
  }

  @Test func theCheckboxStartsTickedWithOtherBooksOrAWriterRenameToRevert() {
    func ticked(_ edits: MetadataEdits, otherBooks: Int) -> Bool {
      BookDetailsDraft(showing: shown(eva, with: edits), fileValues: nil, otherBooks: otherBooks)
        .changesWriter
    }
    let renamed = MetadataEdits(writers: [evasKey: WriterEdit(name: "Eva G. Sáenz")])
    var overridden = renamed
    overridden.books[eva.id] = BookEdit(author: "E. G. Sáenz")
    #expect(ticked(MetadataEdits.none, otherBooks: 3))
    #expect(!ticked(MetadataEdits.none, otherBooks: 0))
    #expect(ticked(renamed, otherBooks: 0))
    #expect(!ticked(overridden, otherBooks: 0))
  }

  @Test func aRenameWithNoOtherBooksStaysTheBooksOwn() async throws {
    let saved = try await save(eva, otherBooks: 0) { $0.author = "Eva G. Sáenz" }
    #expect(saved.books[eva.id] == BookEdit(author: "Eva G. Sáenz", changedAt: now))
    #expect(saved.writers.isEmpty)
  }

  @Test func revertingAWriterRenameWithNoOtherBooksRemovesIt() async throws {
    let edits = MetadataEdits(writers: [
      evasKey: WriterEdit(name: "Eva G. Sáenz", nameChangedAt: earlier)
    ])
    let saved = try await save(eva, with: edits, otherBooks: 0) { $0.author = "Eva Garcia Saenz" }
    #expect(saved.writers == [evasKey: WriterEdit(nameChangedAt: now)])
    #expect(saved.books[eva.id] == nil)
    let reverted = shown(eva, with: saved)
    #expect(reverted.author == "Eva Garcia Saenz")
    #expect(!reverted.edits.isEdited)
  }

  @Test func revertAllKeepsOnlyASortNameTheRenameHadMovedTheBookTo() async throws {
    let movedTo = WriterKey(author: "Eva G. Sáenz")!
    let edits = MetadataEdits(
      books: [eva.id: BookEdit(title: "Ritos", changedAt: earlier)],
      writers: [
        evasKey: WriterEdit(
          name: "Eva G. Sáenz", sortName: "García Sáenz, Eva", nameChangedAt: earlier,
          sortNameChangedAt: earlier),
        movedTo: WriterEdit(sortName: "Sáenz, Eva G.", sortNameChangedAt: earlier),
      ])
    #expect(shown(eva, with: edits).sortAuthor == "Sáenz, Eva G.")
    let books = BookDetailsDraft(
      showing: shown(eva, with: MetadataEdits.none), fileValues: nil, otherBooks: 2)
    let saved = try await save(eva, with: edits, otherBooks: 2) {
      $0 = books
      $0.cover = .revert
    }
    #expect(saved.books[eva.id] == BookEdit(changedAt: now))
    #expect(
      saved.writers == [
        evasKey: WriterEdit(nameChangedAt: now, sortNameChangedAt: now),
        movedTo: WriterEdit(sortName: "Sáenz, Eva G.", sortNameChangedAt: earlier),
      ])
    let reverted = shown(eva, with: saved)
    #expect(reverted.author == "Eva Garcia Saenz")
    #expect(reverted.sortAuthor == "Saenz, Eva Garcia")
    #expect(!reverted.edits.isEdited)
  }

  @Test func aSortNameIsStoredUnderTheShownAuthorsKey() async throws {
    let edits = MetadataEdits(books: [eva.id: BookEdit(author: "E. G. Sáenz")])
    let saved = try await save(eva, with: edits) { $0.sortName = "García Sáenz, E." }
    let shownKey = WriterKey(author: "E. G. Sáenz")!
    #expect(
      saved.writers == [shownKey: WriterEdit(sortName: "García Sáenz, E.", sortNameChangedAt: now)])
    #expect(saved.books[eva.id] == edits.books[eva.id])

    // Renamed in the same draft, the sort name goes to the author shown once saved.
    let renamed = try await save(eva) {
      $0.author = "Evita Sáenz"
      $0.changesWriter = false
      $0.sortName = "Sáenz, E."
    }
    let evitasKey = WriterKey(author: "Evita Sáenz")!
    #expect(
      renamed.writers == [evitasKey: WriterEdit(sortName: "Sáenz, E.", sortNameChangedAt: now)])
    #expect(shown(eva, with: renamed).sortAuthor == "Sáenz, E.")
  }

  @Test func aSortNameEqualToTheDefaultRemovesIt() async throws {
    let edits = MetadataEdits(writers: [
      evasKey: WriterEdit(sortName: "García Sáenz, Eva", sortNameChangedAt: earlier)
    ])
    // While the author is Books' own, the default is Books' sort author.
    let books = try await save(eva, with: edits) { $0.sortName = "Saenz, Eva Garcia" }
    #expect(books.writers == [evasKey: WriterEdit(sortNameChangedAt: now)])
    let cleared = try await save(eva, with: edits) { $0.sortName = "" }
    #expect(cleared.writers == [evasKey: WriterEdit(sortNameChangedAt: now)])

    // Once the author is edited, the default is the derived name.
    let evitasKey = WriterKey(author: "Evita Sáenz")!
    let edited = MetadataEdits(
      books: [eva.id: BookEdit(author: "Evita Sáenz")],
      writers: [evitasKey: WriterEdit(sortName: "Sáenz, E.", sortNameChangedAt: earlier)])
    let derived = try await save(eva, with: edited) { $0.sortName = "Sáenz, Evita" }
    #expect(derived.writers == [evitasKey: WriterEdit(sortNameChangedAt: now)])
  }

  @Test func theSortNameIsLeftAloneUnderFirstName() async throws {
    let saved = try await save(eva, authorSort: .firstName) { $0.sortName = "García Sáenz, Eva" }
    #expect(saved == MetadataEdits.none)
  }

  // MARK: Change dates

  @Test func changedAtMovesOnlyForFileChanges() async throws {
    let edits = MetadataEdits(books: [eva.id: BookEdit(year: "1999", changedAt: earlier)])
    let sorted = try await save(eva, with: edits, fileValues: fileValues) {
      $0.sortTitle = "Ritos"
      $0.cover = .revert
    }
    #expect(sorted.books[eva.id] == BookEdit(sortTitle: "Ritos", year: "1999", changedAt: earlier))

    let reverted = try await save(eva, with: sorted, fileValues: fileValues) { $0.year = "" }
    #expect(reverted.books[eva.id] == BookEdit(sortTitle: "Ritos", changedAt: now))
    #expect(shown(eva, with: reverted).edits.changedAt == now)

    let unsent = try await save(eva) { $0.sortTitle = "Ritos" }
    #expect(unsent.books[eva.id] == BookEdit(sortTitle: "Ritos"))
  }

  @Test func writerChangeDatesMove() async throws {
    let renamed = try await save(eva) { $0.author = "Eva G. Sáenz" }
    #expect(renamed.writers == [evasKey: WriterEdit(name: "Eva G. Sáenz", nameChangedAt: now)])
    #expect(renamed.books.isEmpty)
    let sorted = try await save(eva) { $0.sortName = "García Sáenz, Eva" }
    #expect(
      sorted.writers == [evasKey: WriterEdit(sortName: "García Sáenz, Eva", sortNameChangedAt: now)]
    )

    let edits = MetadataEdits(writers: [
      evasKey: WriterEdit(
        name: "Eva García Sáenz", sortName: "García Sáenz, Eva", nameChangedAt: earlier,
        sortNameChangedAt: earlier)
    ])
    let reverted = try await save(eva, with: edits) {
      $0.author = ""
      $0.sortName = ""
    }
    #expect(reverted.writers == [evasKey: WriterEdit(nameChangedAt: now, sortNameChangedAt: now)])
    #expect(shown(eva, with: reverted).edits.changedAt == now)
    #expect(!shown(eva, with: reverted).edits.isEdited)
  }

  // MARK: Cover

  @Test func coverChangesPassToTheStore() async throws {
    let store = InMemoryMetadataEditStore(coverFolder: folder)
    var draft = BookDetailsDraft(showing: eva, fileValues: nil, otherBooks: 0)
    draft.cover = .replace(Data([1, 2, 3]))
    try await editor(store, at: earlier).save(draft, for: eva, fileValues: nil)
    #expect(await store.covers[eva.id] == Data([1, 2, 3]))
    let replaced = try #require(await store.edits().books[eva.id])
    #expect(replaced.cover != nil)
    #expect(replaced.changedAt == earlier)

    let edited = shown(eva, with: await store.edits())
    var revert = BookDetailsDraft(showing: edited, fileValues: nil, otherBooks: 0)
    revert.cover = .revert
    try await editor(store).save(revert, for: edited, fileValues: nil)
    #expect(await store.covers[eva.id] == nil)
    #expect(await store.edits().books[eva.id] == BookEdit(changedAt: now))
  }

  @Test func storeErrorsMapThrough() async {
    let failures: [(MetadataEditError, EditDetailsError)] = [
      (.unreadableImage, .unreadableImage), (.imageTooLarge, .imageTooLarge),
      (.storage(.writeFailed("disk full")), .storage("disk full")),
    ]
    for (failure, expected) in failures {
      let store = InMemoryMetadataEditStore(coverFolder: folder, failure: failure)
      var draft = BookDetailsDraft(showing: eva, fileValues: nil, otherBooks: 0)
      draft.cover = .replace(Data([1]))
      await #expect(throws: expected) {
        try await editor(store).save(draft, for: eva, fileValues: nil)
      }
    }
  }

  // MARK: Counting

  @Test func otherBooksCountsBothSpellingsOfAWriter() {
    let book = Book.fixture(
      id: "a", author: "Johnny Doe", original: BooksDetails(title: "A", author: "John Doe"))
    let library = [
      book,
      .fixture(id: "b", author: "Doe, John"),
      .fixture(id: "c", author: "JOHN DOE"),
      .fixture(id: "d", author: "Jane Roe"),
      .fixture(id: "e", author: "John Doe", original: BooksDetails(title: "E", author: "Jane Roe")),
      .fixture(id: "f", author: nil),
      .fixture(id: "g", author: " "),
    ]
    #expect(EditBookDetails.otherBooks(by: book, in: library).map(\.id.rawValue) == ["b", "c"])
    #expect(EditBookDetails.otherBooks(by: library[5], in: library).isEmpty)
    #expect(EditBookDetails.otherBooks(by: library[6], in: library).isEmpty)
  }
}
