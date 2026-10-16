import Foundation
import SendleAppleBooks
import SendleDomain
import SendleTestSupport
import Testing

@Suite(.timeLimit(.minutes(1)))
struct AppleBooksLibraryTests {
  let folder: URL
  let books: URL
  let fixture: LibraryDatabaseFixture

  init() throws {
    folder = try makeTemporaryDirectory()
    books = try makeTemporaryDirectory()
    fixture = try LibraryDatabaseFixture(in: folder)
  }

  @Test func mapsAnEPUBFolderAndAPDF() async throws {
    let epub = try makeFolder("Moby-Dick.epub")
    let pdf = try makeFile("Manual.pdf", bytes: 2_048)
    try fixture.insert(
      .init(
        assetID: "E1", title: "Moby-Dick", author: "Herman Melville",
        path: epub.path(percentEncoded: false),
        language: "en", creationDate: 700_000_000, contentType: 1, fileSize: 9_000),
      .init(
        assetID: "P1", title: "Manual", author: nil, path: pdf.path(percentEncoded: false),
        language: nil,
        storeID: "1234", creationDate: 0, contentType: 3, fileSize: 99)
    )

    let result = try await library().books().sorted { $0.id.rawValue < $1.id.rawValue }

    #expect(
      result == [
        Book(
          id: BookID(rawValue: "E1"), title: "Moby-Dick", author: "Herman Melville",
          language: "en", format: .epub, fileURL: URL(filePath: epub.path(percentEncoded: false)),
          sizeBytes: 9_000,
          addedAt: Date(timeIntervalSince1970: 978_307_200 + 700_000_000)),
        Book(
          id: BookID(rawValue: "P1"), title: "Manual", author: nil, language: nil, format: .pdf,
          fileURL: URL(filePath: pdf.path(percentEncoded: false)), sizeBytes: 2_048,
          addedAt: Date(timeIntervalSince1970: 978_307_200), isStorePurchase: true),
      ])
  }

  @Test func marksFilesThatAreMissingOrOnlyInICloud() async throws {
    let local = try makeFolder("Local.epub")
    let placeholder = try makeFolder("Placeholder.epub")
    let cloudOnly = try makeFolder("CloudOnly.epub")
    try fixture.insert(
      .init(assetID: "local", path: local.path(percentEncoded: false)),
      .init(
        assetID: "missing", path: books.appending(path: "Gone.epub").path(percentEncoded: false)),
      .init(assetID: "placeholder", path: placeholder.path(percentEncoded: false)),
      .init(assetID: "cloud-state", path: cloudOnly.path(percentEncoded: false), state: 3)
    )
    let probe = PlaceholderProbe(placeholders: [placeholder.path(percentEncoded: false)])

    let result = try await library(probe: probe).books()

    let availability = Dictionary(
      uniqueKeysWithValues: result.map { ($0.id.rawValue, $0.availability) })
    #expect(
      availability == [
        "local": .ready, "missing": .missing, "placeholder": .inCloudOnly,
        "cloud-state": .inCloudOnly,
      ])
  }

  @Test func fillsGapsFromTheFile() async throws {
    let epub = try makeFolder("Untitled Book.epub")
    try fixture.insert(
      .init(
        title: "  ", author: "", path: epub.path(percentEncoded: false), language: " ", storeID: "",
        creationDate: nil, contentType: nil))

    let book = try #require(try await library().books().first)

    #expect(book.title == "Untitled Book")
    #expect(book.author == nil)
    #expect(book.language == nil)
    #expect(book.format == .epub)
    #expect(!book.isStorePurchase)
    #expect(book.addedAt == .distantPast)
    #expect(book.sizeBytes == nil)
  }

  @Test func skipsFormatsSendleCannotSendAndRelativePaths() async throws {
    try fixture.insert(
      .init(assetID: "audio", path: "/Books/Talk.m4b", contentType: 6),
      .init(assetID: "relative", path: "Books/Moby-Dick.epub", contentType: 1),
      .init(assetID: "pdf-by-name", path: "/Books/Manual.PDF", contentType: nil)
    )

    let result = try await library().books()

    #expect(result.map(\.id.rawValue) == ["pdf-by-name"])
    #expect(result.first?.format == .pdf)
  }

  @Test func prefersBooksContentTypeToTheExtension() async throws {
    try fixture.insert(
      .init(assetID: "epub", path: "/Books/Book.bin", contentType: 1),
      .init(assetID: "pdf", path: "/Books/Scan.epub", contentType: 3)
    )

    let formats = Dictionary(
      uniqueKeysWithValues: try await library().books().map { ($0.id.rawValue, $0.format) })

    #expect(formats == ["epub": .epub, "pdf": .pdf])
  }

  @Test func usesBooksSizeWhenTheFileIsMissing() async throws {
    let gone = books.appending(path: "Gone.pdf").path(percentEncoded: false)
    try fixture.insert(.init(assetID: "gone", path: gone, contentType: 3, fileSize: 500))

    let book = try #require(try await library().books().first)

    #expect(book.availability == .missing)
    #expect(book.sizeBytes == 500)
  }

  @Test func keepsUnicodeAndQuotesIntact() async throws {
    try fixture.insert(
      .init(title: "L'Étranger — “Édition” 📖", author: "Albert Camus", path: "/Books/É.epub"))

    let book = try #require(try await library().books().first)

    #expect(book.title == "L'Étranger — “Édition” 📖")
  }

  @Test func reportsTheLocationsErrors() async throws {
    let missing = AppleBooksLibrary(
      location: .directory(folder.appending(path: "missing")), probe: PlaceholderProbe())

    await #expect(throws: LibraryError.notFound) { try await missing.books() }
  }

  @Test func announcesChangesToTheLibrary() async throws {
    var changes = library().changes().makeAsyncIterator()

    try fixture.insert(.init())

    #expect(await changes.next() != nil)
  }

  @Test func givesEachCallItsOwnStream() async throws {
    let library = library()
    let first = library.changes()
    let second = library.changes()

    try fixture.insert(.init())

    var firstIterator = first.makeAsyncIterator()
    var secondIterator = second.makeAsyncIterator()
    #expect(await firstIterator.next() != nil)
    #expect(await secondIterator.next() != nil)
  }

  @Test func endsTheChangeStreamWhenTheFolderCannotBeWatched() async {
    let library = AppleBooksLibrary(
      location: .directory(folder.appending(path: "missing")), probe: PlaceholderProbe())

    var changes = library.changes().makeAsyncIterator()

    #expect(await changes.next() == nil)
  }

  private func library(probe: any FileProbe = DatalessAwareFileProbe()) -> AppleBooksLibrary {
    AppleBooksLibrary(location: .directory(folder), probe: probe, batchDelay: .milliseconds(50))
  }

  private func makeFolder(_ name: String) throws -> URL {
    let url = books.appending(path: name)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func makeFile(_ name: String, bytes: Int) throws -> URL {
    let url = books.appending(path: name)
    try Data(count: bytes).write(to: url)
    return url
  }
}

/// Reports the given paths as iCloud placeholders and everything else as it is on disk.
private struct PlaceholderProbe: FileProbe {
  var placeholders: Set<String> = []

  func status(of url: URL) -> FileStatus? {
    guard let status = DatalessAwareFileProbe().status(of: url) else { return nil }
    guard placeholders.contains(url.path(percentEncoded: false)) else { return status }
    return FileStatus(isDirectory: status.isDirectory, isDataless: true, size: status.size)
  }
}
