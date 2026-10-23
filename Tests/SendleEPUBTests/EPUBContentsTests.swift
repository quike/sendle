import Foundation
import SendleDomain
import SendleEPUB
import SendleTestSupport
import Testing

struct EPUBContentsTests {
  let folder: URL
  let root: URL

  init() throws {
    folder = try makeTemporaryDirectory()
    root = folder.appending(path: "Moby-Dick.epub", directoryHint: .isDirectory)
  }

  @Test func listsTheBooksFilesWithoutAppleAdditions() throws {
    var book = EPUBFixture.book()
    for extra in [
      "iTunesMetadata.plist", "iTunesMetadata-original.plist",
      "com.apple.ibooks.display-options.plist",
      "bookmarks.plist", "bookmarks-2", ".DS_Store", "OEBPS/.DS_Store",
    ] {
      book.files[extra] = Data("apple".utf8)
    }
    book.files["OEBPS/settings.plist"] = Data("kept: only root plists are Apple's".utf8)
    try book.write(to: root)

    #expect(
      EPUBContents.entries(in: root)
        == [
          "META-INF/container.xml", "OEBPS/chapter1.xhtml", "OEBPS/content.opf",
          "OEBPS/settings.plist",
        ])
  }

  @Test func leavesOutSymbolicLinks() throws {
    try EPUBFixture.book().write(to: root)
    let secrets = folder.appending(path: "secrets", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: secrets, withIntermediateDirectories: true)
    try Data("private".utf8).write(to: secrets.appending(path: "key.txt"))
    try FileManager.default.createSymbolicLink(
      at: root.appending(path: "OEBPS/key.txt"),
      withDestinationURL: secrets.appending(path: "key.txt"))
    try FileManager.default.createSymbolicLink(
      at: root.appending(path: "OEBPS/secrets"), withDestinationURL: secrets)

    #expect(
      EPUBContents.entries(in: root)
        == ["META-INF/container.xml", "OEBPS/chapter1.xhtml", "OEBPS/content.opf"])
  }

  @Test func listsNothingForAMissingFolder() {
    #expect(EPUBContents.entries(in: folder.appending(path: "missing")).isEmpty)
  }
}

struct DittoExtractorTests {
  let folder: URL

  init() throws {
    folder = try makeTemporaryDirectory()
  }

  @Test func unzipsAnArchive() throws {
    let archive = folder.appending(path: "book.epub")
    try writeArchive(
      [
        ("mimetype", Data("application/epub+zip".utf8)),
        ("OEBPS/chapter1.xhtml", Data("<html/>".utf8)),
      ],
      to: archive)
    let out = folder.appending(path: "out", directoryHint: .isDirectory)

    try DittoExtractor().extract(archive, into: out)

    #expect(
      try Data(contentsOf: out.appending(path: "OEBPS/chapter1.xhtml")) == Data("<html/>".utf8))
  }

  @Test func reportsADamagedArchiveAsAnInvalidBook() throws {
    let archive = folder.appending(path: "book.epub")
    try Data("not a zip".utf8).write(to: archive)

    #expect(throws: SendFailure.invalidBook("The EPUB file couldn't be unzipped")) {
      try DittoExtractor().extract(archive, into: folder.appending(path: "out"))
    }
  }
}
