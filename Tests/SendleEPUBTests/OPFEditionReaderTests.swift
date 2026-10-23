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

  @Test func pdfsHaveNoEdition() async throws {
    let url = folder.appending(path: "book.pdf")
    try Data("%PDF-1.4".utf8).write(to: url)

    #expect(await reader().editions(of: [.fixture(id: "pdf", format: .pdf, fileURL: url)]).isEmpty)
    #expect(!FileManager.default.fileExists(atPath: cacheFile.path))
  }

  @Test func readsTheEditionOfAZippedBook() async throws {
    let zipped = try zippedEPUB(id: "zipped")

    #expect(
      await reader().editions(of: [zipped]) == [zipped.id: Edition(key: "urn:uuid:moby-dick")])
    #expect(try temporaryFiles().isEmpty)
  }

  @Test func unzipsOnlyTheContainerAndThePackage() throws {
    let zipped = try zippedEPUB(id: "zipped")
    let out = folder.appending(path: "out", directoryHint: .isDirectory)

    try PackageExtractor().extract(zipped.fileURL, into: out)

    let files = try FileManager.default.subpathsOfDirectory(atPath: out.path)
      .filter { !$0.hasSuffix("/") && !["META-INF", "OEBPS"].contains($0) }
    #expect(Set(files) == ["META-INF/container.xml", "OEBPS/content.opf"])
  }

  @Test func aPackageWithAnUnusualNameIsStillRead() async throws {
    var book = EPUBFixture.book()
    book.files["OEBPS/Content.OPF"] = book.files.removeValue(forKey: "OEBPS/content.opf")
    book.files["META-INF/container.xml"] = Data(
      EPUBFixture.container.replacingOccurrences(of: "content.opf", with: "Content.OPF").utf8)
    let zipped = try zippedEPUB(id: "unusual", files: book.files)

    #expect(
      await reader().editions(of: [zipped]) == [zipped.id: Edition(key: "urn:uuid:moby-dick")])
  }

  @Test func aFileThatIsNoBookHasNoEditionAndIsNotCached() async throws {
    let url = folder.appending(path: "broken.epub")
    try Data("not a zip".utf8).write(to: url)
    let broken = Book.fixture(id: "broken", fileURL: url)

    #expect(await reader().editions(of: [broken]).isEmpty)
    #expect(!FileManager.default.fileExists(atPath: cacheFile.path))
    #expect(try temporaryFiles().isEmpty)
  }

  @Test func readsEachBookOnceUntilItChanges() async throws {
    let moby = try epub(id: "moby")
    _ = await reader().editions(of: [moby])
    try removePackage(of: moby, keepingDate: true)

    #expect(await reader().editions(of: [moby])[moby.id]?.key == "urn:uuid:moby-dick")

    try touch(moby, secondsLater: 10)

    #expect(await reader().editions(of: [moby])[moby.id] == nil)
  }

  @Test func aBookWithoutAKeyIsCachedWithoutOne() async throws {
    let anonymous = try epub(id: "anonymous", metadata: "<dc:title>Moby-Dick</dc:title>")

    #expect(await reader().editions(of: [anonymous]) == [anonymous.id: Edition()])
    #expect(FileManager.default.fileExists(atPath: cacheFile.path))
  }

  @Test func aDamagedCacheIsReadAgain() async throws {
    let moby = try epub(id: "moby")
    try Data("not json".utf8).write(to: cacheFile)

    #expect(await reader().editions(of: [moby])[moby.id]?.key == "urn:uuid:moby-dick")
  }

  @Test func aCacheFromBeforeEditionsHeldAYearIsReadAgain() async throws {
    let moby = try epub(
      id: "moby", metadata: EPUBFixture.metadata + "<dc:date>1851-10-18</dc:date>")
    let modified = try #require(
      try FileManager.default.attributesOfItem(atPath: moby.fileURL.path)[.modificationDate]
        as? Date)
    let stale: [String: Any] = [
      "version": 1,
      "entries": [
        moby.fileURL.path(percentEncoded: false): [
          "modified": Int(modified.timeIntervalSince1970), "edition": ["key": "urn:uuid:moby-dick"],
        ]
      ],
    ]
    try JSONSerialization.data(withJSONObject: stale).write(to: cacheFile)

    #expect(
      await reader().editions(of: [moby])
        == [moby.id: Edition(key: "urn:uuid:moby-dick", year: "1851")])
  }

  /// Unzips into this test's own folder, where parallel tests leave nothing.
  private func reader() -> OPFEditionReader {
    OPFEditionReader(cacheFile: cacheFile, scratchFolder: folder)
  }

  private func epub(
    id: String, availability: Availability = .ready, metadata: String = EPUBFixture.metadata
  ) throws -> Book {
    let root = folder.appending(path: "\(id).epub", directoryHint: .isDirectory)
    try EPUBFixture.book(metadata: metadata).write(to: root)
    return .fixture(id: id, fileURL: root, availability: availability)
  }

  private func zippedEPUB(id: String, files: [String: Data] = EPUBFixture.book().files) throws
    -> Book
  {
    let names = ["mimetype"] + files.keys.filter { $0 != "mimetype" }.sorted()
    let url = folder.appending(path: "\(id).epub")
    try writeArchive(names.compactMap { name in files[name].map { (name, $0) } }, to: url)
    return .fixture(id: id, fileURL: url)
  }

  /// What a read leaves in the temporary folder.
  private func temporaryFiles() throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
      .filter { $0.hasPrefix("SendleEditions-") }
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
