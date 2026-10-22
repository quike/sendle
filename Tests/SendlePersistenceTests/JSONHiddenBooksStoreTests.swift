import Foundation
import SendleDomain
import SendlePersistence
import SendleTestSupport
import Testing

@Suite(.timeLimit(.minutes(1)))
struct JSONHiddenBooksStoreTests {
  let directory: URL
  let a = BookID(rawValue: "a")
  let b = BookID(rawValue: "b")

  init() throws {
    directory = try makeTemporaryDirectory()
  }

  private var file: URL { directory.appending(path: "hidden.json") }

  @Test func startsWithNothingHidden() async {
    #expect(await JSONHiddenBooksStore(directory: directory).hidden().isEmpty)
    #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
  }

  @Test func hidesAndShowsBooks() async throws {
    let store = JSONHiddenBooksStore(directory: directory)

    try await store.set([a, b], hidden: true)
    try await store.set([a], hidden: true)
    #expect(await JSONHiddenBooksStore(directory: directory).hidden() == [a, b])

    try await store.set([a, BookID(rawValue: "never hidden")], hidden: false)
    #expect(await JSONHiddenBooksStore(directory: directory).hidden() == [b])
  }

  @Test func writesAVersionedFileWithSortedIDs() async throws {
    try await JSONHiddenBooksStore(directory: directory).set([b, a], hidden: true)

    let data = try Data(contentsOf: file)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(json["version"] as? Int == 1)
    #expect(json["books"] as? [String] == ["a", "b"])
  }

  @Test func readsANewerFileButNeverRewritesIt() async throws {
    let newer = #"{"books":["a"],"version":2}"#
    try Data(newer.utf8).write(to: file)
    let log = FakeActivityLog()
    let store = JSONHiddenBooksStore(directory: directory, log: log)

    #expect(await store.hidden() == [a])
    await #expect(
      throws: StorageError.writeFailed("the hidden list was saved by a newer version of Sendle")
    ) {
      try await store.set([b], hidden: true)
    }

    #expect(await store.hidden() == [a])
    #expect(try String(contentsOf: file, encoding: .utf8) == newer)
    #expect(
      log.summary.contains {
        $0.hasPrefix("error APP Couldn't save hidden.json: it is from a newer version")
      })
  }

  @Test func quarantinesACorruptFile() async throws {
    try Data("{ not json".utf8).write(to: file)
    let store = JSONHiddenBooksStore(directory: directory)

    #expect(await store.hidden().isEmpty)

    let names = try FileManager.default.contentsOfDirectory(
      atPath: directory.path(percentEncoded: false))
    let moved = try #require(names.first { $0.wholeMatch(of: /hidden\.corrupt-\d+\.json/) != nil })
    #expect(
      try String(contentsOf: directory.appending(path: moved), encoding: .utf8) == "{ not json")
    #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))

    try await store.set([a], hidden: true)
    #expect(await JSONHiddenBooksStore(directory: directory).hidden() == [a])
  }
}
