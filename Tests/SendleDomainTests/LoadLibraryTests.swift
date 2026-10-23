import Foundation
import SendleDomain
import SendleTestSupport
import Testing

@Suite(.timeLimit(.minutes(1)))
struct LoadLibraryTests {
  @Test func marksBooksWithDRMEvidenceAsProtected() async throws {
    let open = Book.fixture(id: "open")
    let locked = Book.fixture(id: "locked")
    let load = LoadLibrary(
      library: FakeBooksLibrary(.success([open, locked])),
      inspector: StubProtectionInspector(protectedIDs: [locked.id]))

    let books = try await load()

    #expect(books.first { $0.id == open.id }?.availability == .ready)
    #expect(books.first { $0.id == locked.id }?.availability == .protected)
  }

  @Test func logsWhatItReadOnlyWhenThatChanges() async throws {
    let library = FakeBooksLibrary(
      .success([
        .fixture(id: "a"), .fixture(id: "b"), .fixture(id: "c", availability: .inCloudOnly),
      ]))
    let log = FakeActivityLog()
    let load = LoadLibrary(
      library: library, inspector: StubProtectionInspector(protectedIDs: [BookID(rawValue: "b")]),
      log: log)

    _ = try await load()
    _ = try await load()
    library.result = .success([.fixture(id: "a")])
    _ = try await load()

    #expect(log.summary.count == 2)
    #expect(log.summary[0].hasPrefix("info LIB Read 3 books (1 protected, 1 only in iCloud) in "))
    #expect(log.summary[1].wholeMatch(of: /info LIB Read 1 book in \d+\.\d s/) != nil)
  }

  @Test func logsWhyTheLibraryCouldNotBeRead() async {
    let log = FakeActivityLog()
    let load = LoadLibrary(
      library: FakeBooksLibrary(.failure(.accessDenied)), inspector: StubProtectionInspector(),
      log: log)

    _ = try? await load()

    #expect(
      log.summary == ["error LIB Couldn't read the Books library: Sendle has no Full Disk Access"])
  }

  @Test func keepsTheReasonForBooksThatAreNotOnThisMac() async throws {
    let cloud = Book.fixture(id: "cloud", availability: .inCloudOnly)
    let load = LoadLibrary(
      library: FakeBooksLibrary(.success([cloud])),
      inspector: StubProtectionInspector(protectedIDs: [cloud.id]))

    #expect(try await load().map(\.availability) == [.inCloudOnly])
  }

  @Test func sortsNewestFirstThenByTitle() async throws {
    let old = Date(timeIntervalSince1970: 1_000)
    let new = Date(timeIntervalSince1970: 2_000)
    let load = LoadLibrary(
      library: FakeBooksLibrary(
        .success([
          .fixture(id: "a", title: "Book 10", addedAt: new),
          .fixture(id: "b", title: "Ancient", addedAt: old),
          .fixture(id: "c", title: "Book 9", addedAt: new),
        ])),
      inspector: StubProtectionInspector())

    #expect(try await load().map(\.id.rawValue) == ["c", "a", "b"])
  }

  @Test func appliesEditsBeforeSorting() async throws {
    let added = Date(timeIntervalSince1970: 1_000)
    let plain = Book.fixture(id: "plain", title: "B", addedAt: added)
    let retitled = Book.fixture(id: "retitled", title: "C", addedAt: added)
    let load = LoadLibrary(
      library: FakeBooksLibrary(.success([plain, retitled])),
      inspector: StubProtectionInspector(),
      edits: InMemoryMetadataEditStore(
        MetadataEdits(books: [retitled.id: BookEdit(title: "A")])))

    let books = try await load()

    #expect(books.map(\.id.rawValue) == ["retitled", "plain"])
    #expect(books.first?.title == "A")
    #expect(books.first?.original.title == "C")
  }

  @Test func readsTheAuthorSortSettingEachTime() async throws {
    let settings = InMemorySettingsStore()
    let load = LoadLibrary(
      library: FakeBooksLibrary(
        .success([.fixture(author: "Eva García Sáenz", sortAuthor: "Sáenz, Eva García")])),
      inspector: StubProtectionInspector(), settings: settings)

    #expect(try await load().first?.sortAuthor == "Sáenz, Eva García")
    try await settings.update { $0.authorSort = .firstName }
    #expect(try await load().first?.sortAuthor == "Eva García Sáenz")
    try await settings.update { $0.authorSort = .surname }
    #expect(try await load().first?.sortAuthor == "Sáenz, Eva García")
  }

  @Test func sortsAuthorsBySurnameWithoutASettingsStore() async throws {
    let load = LoadLibrary(
      library: FakeBooksLibrary(
        .success([.fixture(author: "Eva García Sáenz", sortAuthor: "Sáenz, Eva García")])),
      inspector: StubProtectionInspector())

    #expect(try await load().first?.sortAuthor == "Sáenz, Eva García")
  }

  @Test func ignoresEditsOfBooksNotInTheLibrary() async throws {
    let book = Book.fixture(id: "here")
    let load = LoadLibrary(
      library: FakeBooksLibrary(.success([book])),
      inspector: StubProtectionInspector(),
      edits: InMemoryMetadataEditStore(
        MetadataEdits(books: [BookID(rawValue: "gone"): BookEdit(title: "Ghost")])))

    let books = try await load()

    #expect(books.map(\.id) == [book.id])
    #expect(books.first?.title == book.title)
    #expect(books.first?.edits.isEdited == false)
  }

  @Test func editedBooksKeepTheirProtectedMark() async throws {
    let locked = Book.fixture(id: "locked")
    let load = LoadLibrary(
      library: FakeBooksLibrary(.success([locked])),
      inspector: StubProtectionInspector(protectedIDs: [locked.id]),
      edits: InMemoryMetadataEditStore(
        MetadataEdits(books: [locked.id: BookEdit(title: "Renamed")])))

    let books = try await load()

    #expect(books.first?.title == "Renamed")
    #expect(books.first?.availability == .protected)
  }

  @Test func reportsWhenBooksIsOffLimits() async {
    let load = LoadLibrary(
      library: FakeBooksLibrary(.failure(.accessDenied)), inspector: StubProtectionInspector())

    await #expect(throws: LibraryError.accessDenied) { try await load() }
  }

  @Test func passesOnLibraryChanges() async {
    let library = FakeBooksLibrary(.success([]))
    let load = LoadLibrary(library: library, inspector: StubProtectionInspector())
    var changes = load.changes().makeAsyncIterator()

    library.announceChange()

    #expect(await changes.next() != nil)
  }
}
