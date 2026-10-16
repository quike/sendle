import Foundation
import SendleDomain
import SendleTestSupport
import Testing

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
