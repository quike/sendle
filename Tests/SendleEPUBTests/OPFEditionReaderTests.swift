import Foundation
import SendleDomain
import SendleEPUB
import SendleTestSupport
import Testing

@Suite(.timeLimit(.minutes(1)))
struct OPFEditionReaderTests {
  let folder: URL
  let cacheFile: URL

  init() throws {
    folder = try makeTemporaryDirectory()
    cacheFile = folder.appending(path: "editions.json")
  }

  @Test func readsTheEditionOfABookOnThisMac() async throws {
    let moby = try epub(id: "moby")

    #expect(await reader().editions(of: [moby]) == [moby.id: Edition(key: "urn:uuid:moby-dick")])
  }

  @Test func neverReadsABookInICloud() async throws {
    let cloud = try epub(id: "cloud", availability: .inCloudOnly)

    #expect(await reader().editions(of: [cloud]).isEmpty)
  }

  @Test func pdfsHaveNoEdition() async {
    #expect(await reader().editions(of: [.fixture(id: "pdf", format: .pdf)]).isEmpty)
  }

  @Test func readsEachBookOnceUntilItChanges() async throws {
    let moby = try epub(id: "moby")
    _ = await reader().editions(of: [moby])
    try removePackage(of: moby, keepingDate: true)

    #expect(await reader().editions(of: [moby])[moby.id]?.key == "urn:uuid:moby-dick")

    try touch(moby, secondsLater: 10)

    #expect(await reader().editions(of: [moby])[moby.id] == Edition())
  }

  @Test func aDamagedCacheIsReadAgain() async throws {
    let moby = try epub(id: "moby")
    try Data("not json".utf8).write(to: cacheFile)

    #expect(await reader().editions(of: [moby])[moby.id]?.key == "urn:uuid:moby-dick")
  }

  private func reader() -> OPFEditionReader {
    OPFEditionReader(cacheFile: cacheFile)
  }

  private func epub(id: String, availability: Availability = .ready) throws -> Book {
    let root = folder.appending(path: "\(id).epub", directoryHint: .isDirectory)
    try EPUBFixture.book().write(to: root)
    return .fixture(id: id, fileURL: root, availability: availability)
  }

  private func removePackage(of book: Book, keepingDate: Bool) throws {
    let date = try FileManager.default.attributesOfItem(atPath: book.fileURL.path)[
      .modificationDate]
    try FileManager.default.removeItem(at: book.fileURL.appending(path: "OEBPS/content.opf"))
    if keepingDate {
      try FileManager.default.setAttributes(
        [.modificationDate: date as Any], ofItemAtPath: book.fileURL.path)
    }
  }

  private func touch(_ book: Book, secondsLater seconds: TimeInterval) throws {
    let date = try #require(
      try FileManager.default.attributesOfItem(atPath: book.fileURL.path)[.modificationDate]
        as? Date)
    try FileManager.default.setAttributes(
      [.modificationDate: date.addingTimeInterval(seconds)], ofItemAtPath: book.fileURL.path)
  }
}
