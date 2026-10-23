import Foundation
import SendleDomain
import SendleEPUB
import SendleTestSupport
import Testing

struct OPFReaderTests {
  let folder: URL
  let root: URL

  init() throws {
    folder = try makeTemporaryDirectory()
    root = folder.appending(path: "Moby-Dick.epub", directoryHint: .isDirectory)
  }

  @Test func findsAnEPUB3CoverImage() throws {
    var book = EPUBFixture.book(
      manifest: EPUBFixture.manifest
        + #"<item id="art" href="images/cover.jpg" media-type="image/jpeg" properties="cover-image"/>"#
    )
    book.files["OEBPS/images/cover.jpg"] = Data("jpeg".utf8)
    try book.write(to: root)

    #expect(OPFReader.coverImage(inEPUBAt: root) == root.appending(path: "OEBPS/images/cover.jpg"))
  }

  @Test func findsAnEPUB2CoverMeta() throws {
    var book = EPUBFixture.book(
      metadata: EPUBFixture.metadata + #"<meta name="cover" content="cover-img"/>"#,
      manifest: EPUBFixture.manifest
        + #"<item id="cover-img" href="../Art/cover.png" media-type="image/png"/>"#)
    book.files["Art/cover.png"] = Data("png".utf8)
    try book.write(to: root)

    #expect(OPFReader.coverImage(inEPUBAt: root) == root.appending(path: "Art/cover.png"))
  }

  @Test func ignoresAnEPUB2CoverMetaThatNamesAPage() throws {
    try EPUBFixture.book(
      metadata: EPUBFixture.metadata + #"<meta name="cover" content="chapter1"/>"#
    ).write(to: root)

    #expect(OPFReader.coverImage(inEPUBAt: root) == nil)
  }

  @Test func decodesPercentEncodedReferences() throws {
    var book = EPUBFixture.book(
      manifest: EPUBFixture.manifest
        + #"<item id="art" href="my%20cover.jpg" media-type="image/jpeg" properties="cover-image"/>"#
    )
    book.files["OEBPS/my cover.jpg"] = Data("jpeg".utf8)
    try book.write(to: root)

    #expect(OPFReader.coverImage(inEPUBAt: root) == root.appending(path: "OEBPS/my cover.jpg"))
  }

  @Test func returnsNilWithoutACoverOrItsFile() throws {
    try EPUBFixture.book().write(to: root)
    #expect(OPFReader.coverImage(inEPUBAt: root) == nil)

    try EPUBFixture.book(
      manifest:
        #"<item id="art" href="gone.jpg" media-type="image/jpeg" properties="cover-image"/>"#
    ).write(to: root)
    #expect(OPFReader.coverImage(inEPUBAt: root) == nil)
  }

  @Test func neverPointsOutsideTheBook() throws {
    try Data("secret".utf8).write(to: folder.appending(path: "secret.jpg"))
    try EPUBFixture.book(
      manifest:
        #"<item id="art" href="../../secret.jpg" media-type="image/jpeg" properties="cover-image"/>"#
    ).write(to: root)
    #expect(OPFReader.coverImage(inEPUBAt: root) == nil)

    try EPUBFixture.book(
      manifest:
        #"<item id="art" href="link.jpg" media-type="image/jpeg" properties="cover-image"/>"#
    ).write(to: root)
    try FileManager.default.createSymbolicLink(
      at: root.appending(path: "OEBPS/link.jpg"),
      withDestinationURL: folder.appending(path: "secret.jpg"))
    #expect(OPFReader.coverImage(inEPUBAt: root) == nil)
  }

  @Test func neverFollowsALinkedFolderOutOfTheBook() throws {
    let pictures = folder.appending(path: "Pictures", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: pictures, withIntermediateDirectories: true)
    try Data("photo".utf8).write(to: pictures.appending(path: "photo.png"))
    try EPUBFixture.book(
      manifest:
        #"<item id="art" href="art/photo.png" media-type="image/png" properties="cover-image"/>"#
    ).write(to: root)
    try FileManager.default.createSymbolicLink(
      at: root.appending(path: "OEBPS/art"), withDestinationURL: pictures)

    #expect(OPFReader.coverImage(inEPUBAt: root) == nil)
  }

  @Test func followsTheContainerToThePackage() throws {
    var book = EPUBFixture.book()
    book[text: "META-INF/container.xml"] = EPUBFixture.container.replacingOccurrences(
      of: "OEBPS/content.opf", with: "book/package.opf")
    book.files["book/package.opf"] = book.files.removeValue(forKey: "OEBPS/content.opf")
    try book.write(to: root)

    let package = try #require(OPFReader.package(inEPUBAt: root))

    #expect(package.path == "book/package.opf")
    #expect(package.items.map(\.path) == ["book/chapter1.xhtml"])
  }

  @Test func readsTheManifestAndLanguage() throws {
    let opf = EPUBFixture.package(
      metadata: "<dc:title>Moby-Dick</dc:title>",
      manifest: """
        <item id="c1" href="text/one.xhtml" media-type="application/xhtml+xml" properties="svg scripted"/>
        <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
        """)

    let package = try #require(OPFReader.package(Data(opf.utf8), at: "OEBPS/content.opf"))

    #expect(
      package.items == [
        .init(
          id: "c1", path: "OEBPS/text/one.xhtml", mediaType: "application/xhtml+xml",
          properties: ["svg", "scripted"]),
        .init(
          id: "ncx", path: "OEBPS/toc.ncx", mediaType: "application/x-dtbncx+xml", properties: []),
      ])
    #expect(!package.hasLanguage)
  }

  @Test(arguments: [
    ("<dc:language>en</dc:language>", true),
    ("<dc:language> </dc:language>", false),
    ("<dc:language/>", false),
    ("<language>en</language>", false),
  ])
  func detectsADeclaredLanguage(metadata: String, expected: Bool) throws {
    let opf = EPUBFixture.package(metadata: metadata, manifest: EPUBFixture.manifest)

    #expect(OPFReader.package(Data(opf.utf8), at: "content.opf")?.hasLanguage == expected)
  }

  @Test func rejectsAMissingContainerOrABrokenPackage() throws {
    #expect(OPFReader.package(inEPUBAt: root) == nil)

    var book = EPUBFixture.book()
    book[text: "OEBPS/content.opf"] = "<package><metadata>"
    try book.write(to: root)
    #expect(OPFReader.package(inEPUBAt: root) == nil)
  }

  @Test func readsOnlyRegularFilesInsideTheBook() throws {
    var book = EPUBFixture.book()
    book.files["META-INF/container.xml"] = nil
    try book.write(to: root)
    let outside = folder.appending(path: "container.xml")
    try Data(EPUBFixture.container.utf8).write(to: outside)
    try FileManager.default.createDirectory(
      at: root.appending(path: "META-INF"), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
      at: root.appending(path: "META-INF/container.xml"), withDestinationURL: outside)

    #expect(OPFReader.package(inEPUBAt: root) == nil)
  }

  @Test func readsTheEditionFromThePackage() throws {
    try EPUBFixture.book(
      metadata: EPUBFixture.metadata
        + """
        <dc:identifier xmlns:opf="http://www.idpf.org/2007/opf" opf:scheme="ISBN">0-306-40615-2</dc:identifier>
        <dc:publisher> Penguin </dc:publisher>
        """
    ).write(to: root)

    #expect(
      OPFReader.package(inEPUBAt: root)?.edition
        == Edition(key: "urn:uuid:moby-dick", isbn: "9780306406157", publisher: "Penguin"))
  }

  @Test func theISBNIsTheKeyWithoutAUniqueIdentifier() throws {
    try EPUBFixture.book(
      metadata: """
        <dc:identifier id="other">urn:isbn:9780306406157</dc:identifier><dc:title>Moby-Dick</dc:title>
        """
    ).write(to: root)

    #expect(
      OPFReader.package(inEPUBAt: root)?.edition
        == Edition(key: "9780306406157", isbn: "9780306406157"))
  }

  @Test func anInvalidISBNIsNoISBN() throws {
    try EPUBFixture.book(
      metadata: EPUBFixture.metadata + "<dc:identifier>urn:isbn:0306406153</dc:identifier>"
    ).write(to: root)

    #expect(OPFReader.package(inEPUBAt: root)?.edition.isbn == nil)
  }

  @Test func readsTheYearOfTheFirstDate() throws {
    try EPUBFixture.book(
      metadata: EPUBFixture.metadata + """
        <dc:date opf:event="publication" xmlns:opf="http://www.idpf.org/2007/opf">1851-10-18T00:00:00+00:00</dc:date>
        <dc:date>2020-01-01</dc:date>
        """
    ).write(to: root)

    #expect(OPFReader.package(inEPUBAt: root)?.edition.year == "1851")
  }

  @Test(arguments: ["", "c. 1851", "18511018", "-0044", "١٨٥١"])
  func aDateWithoutAFourDigitYearGivesNoYear(date: String) throws {
    try EPUBFixture.book(metadata: EPUBFixture.metadata + "<dc:date>\(date)</dc:date>")
      .write(to: root)

    #expect(OPFReader.package(inEPUBAt: root)?.edition.year == nil)
  }

  @Test func onlyTheFirstDateCounts() throws {
    try EPUBFixture.book(
      metadata: EPUBFixture.metadata + "<dc:date>unknown</dc:date><dc:date>2020-01-01</dc:date>"
    ).write(to: root)

    #expect(OPFReader.package(inEPUBAt: root)?.edition.year == nil)
  }
}

struct ArchivePathTests {
  @Test(arguments: [
    ("chapter1.xhtml", "OEBPS", "OEBPS/chapter1.xhtml"),
    ("../images/a.jpg", "OEBPS/text", "OEBPS/images/a.jpg"),
    ("./a%20b.xhtml#part", "OEBPS", "OEBPS/a b.xhtml"),
    ("content.opf", "", "content.opf"),
  ])
  func resolvesReferencesInsideTheBook(reference: String, directory: String, expected: String) {
    #expect(ArchivePath.resolve(reference, from: directory) == expected)
  }

  @Test(arguments: [
    "../../outside.jpg", "/etc/passwd", "https://example.com/a.jpg", "mailto:me@example.com",
    "#top", "", "%2e%2e/%2e%2e/x.jpg", "..%2F..%2Fx.jpg",
  ])
  func rejectsReferencesThatLeaveTheBook(reference: String) {
    #expect(ArchivePath.resolve(reference, from: "OEBPS") == nil)
  }

  @Test func findsAPathsDirectory() {
    #expect(ArchivePath.directory(of: "OEBPS/text/one.xhtml") == "OEBPS/text")
    #expect(ArchivePath.directory(of: "content.opf") == "")
  }
}
