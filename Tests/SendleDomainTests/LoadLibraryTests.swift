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
    #expect(log.summary[1].hasPrefix("info LIB Read 1 book in "))
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
