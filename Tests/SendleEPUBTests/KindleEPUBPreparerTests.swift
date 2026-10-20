import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import SendleDomain
import SendleEPUB
import SendleTestSupport
import Testing
import UniformTypeIdentifiers

struct KindleEPUBPreparerTests {
  let folder: URL
  let staging: URL
  let root: URL
  let log = FakeActivityLog()
  let preparer: KindleEPUBPreparer

  init() throws {
    folder = try makeTemporaryDirectory()
    staging = try makeTemporaryDirectory()
    root = folder.appending(path: "Moby-Dick.epub", directoryHint: .isDirectory)
    preparer = KindleEPUBPreparer(log: log)
  }

  @Test func packagesACleanBookAsItIs() async throws {
    let epub = EPUBFixture.book()
    try epub.write(to: root)

    let prepared = try await preparer.prepare(book(), details: PackageDetails(), in: staging)

    #expect(prepared.url == staging.appending(path: "Moby-Dick - Herman Melville.epub"))
    #expect(prepared.format == .epub)
    #expect(prepared.fixes.isEmpty)
    let archive = try Data(contentsOf: prepared.url)
    #expect(
      localHeaders(in: archive).map(\.name)
        == ["mimetype", "META-INF/container.xml", "OEBPS/chapter1.xhtml", "OEBPS/content.opf"])
    #expect(try unzipped(prepared.url) == epub.files)
  }

  @Test func carriesTheEditionToTheKindle() async throws {
    try EPUBFixture.book().write(to: root)

    let prepared = try await preparer.prepare(book(), details: PackageDetails(), in: staging)

    #expect(prepared.edition?.key == "urn:uuid:moby-dick")
  }

  @Test func leavesOutApplesAdditions() async throws {
    var epub = EPUBFixture.book()
    epub.files["iTunesMetadata.plist"] = Data("plist".utf8)
    epub.files["OEBPS/.DS_Store"] = Data("finder".utf8)
    try epub.write(to: root)

    let prepared = try await preparer.prepare(book(), details: PackageDetails(), in: staging)

    #expect(
      !localHeaders(in: try Data(contentsOf: prepared.url)).map(\.name).contains {
        $0.hasSuffix(".plist") || $0.hasSuffix(".DS_Store")
      })
  }

  @Test func appliesTheKindleFixesAndReportsThem() async throws {
    let epub = EPUBFixture.book(
      metadata: "<dc:title>Moby-Dick</dc:title>",
      chapter:
        ##"<html xmlns="http://www.w3.org/1999/xhtml"><body id="c1"><a href="#c1">Top</a><img/></body></html>"##
    )
    try epub.write(to: root)

    let prepared = try await preparer.prepare(
      book(language: "es"), details: PackageDetails(), in: staging)

    #expect(
      prepared.fixes == [
        .addedXMLDeclaration, .addedLanguage, .removedBodyIDLinks, .removedEmptyImages,
      ])
    let files = try unzipped(prepared.url)
    let chapter = String(decoding: files["OEBPS/chapter1.xhtml"] ?? Data(), as: UTF8.self)
    #expect(
      chapter
        == XMLDeclarationFix.declaration + "\n"
        + #"<html xmlns="http://www.w3.org/1999/xhtml"><body id="c1"><a href="chapter1.xhtml">Top</a></body></html>"#
    )
    #expect(
      String(decoding: files["OEBPS/content.opf"] ?? Data(), as: UTF8.self).contains(
        ">es</dc:language>"))
  }

  @Test func sendsDocumentsInOtherEncodingsByteForByte() async throws {
    var epub = EPUBFixture.book()
    let latin1 =
      Data(#"<?xml version="1.0" encoding="iso-8859-1"?><html><body><p>Caf"#.utf8) + Data([0xE9])
      + Data("</p><img/></body></html>".utf8)
    epub.files["OEBPS/chapter1.xhtml"] = latin1
    try epub.write(to: root)

    let prepared = try await preparer.prepare(book(), details: PackageDetails(), in: staging)

    #expect(try unzipped(prepared.url)["OEBPS/chapter1.xhtml"] == latin1)
    #expect(prepared.fixes.isEmpty)
  }

  @Test func sendsUTF16DocumentsByteForByte() async throws {
    var epub = EPUBFixture.book()
    let utf16 = try #require("<html><body><img/></body></html>".data(using: .utf16LittleEndian))
    epub.files["OEBPS/chapter1.xhtml"] = utf16
    try epub.write(to: root)

    let prepared = try await preparer.prepare(book(), details: PackageDetails(), in: staging)

    #expect(try unzipped(prepared.url)["OEBPS/chapter1.xhtml"] == utf16)
    #expect(prepared.fixes.isEmpty)
  }

  @Test func unzipsAZippedEPUBFirst() async throws {
    let epub = EPUBFixture.book(metadata: "<dc:title>Moby-Dick</dc:title>")
    let file = folder.appending(path: "Zipped.epub")
    try writeArchive(epub.archiveEntries, to: file)

    let prepared = try await preparer.prepare(
      book(at: file), details: PackageDetails(), in: staging)

    #expect(prepared.fixes == [.addedLanguage])
    #expect(
      try unzipped(prepared.url)["OEBPS/chapter1.xhtml"] == epub.files["OEBPS/chapter1.xhtml"])
  }

  @Test func refusesABookWithDRMEvidenceEvenWhenZipped() async throws {
    var epub = EPUBFixture.book()
    epub[text: "META-INF/sinf.xml"] = "<sinf/>"
    let file = folder.appending(path: "Protected.epub")
    try writeArchive(epub.archiveEntries, to: file)

    await #expect(throws: SendFailure.protected) {
      try await preparer.prepare(book(at: file), details: PackageDetails(), in: staging)
    }
  }

  @Test func reportsAMissingBook() async {
    await #expect(throws: SendFailure.missing) {
      try await preparer.prepare(
        book(at: folder.appending(path: "Gone.epub")), details: PackageDetails(), in: staging)
    }
  }

  @Test func reportsABookWithoutAPackageAsInvalid() async throws {
    var epub = EPUBFixture.book()
    epub.files["META-INF/container.xml"] = nil
    try epub.write(to: root)

    await #expect(throws: SendFailure.invalidBook("Its package document is missing or unreadable"))
    {
      try await preparer.prepare(book(), details: PackageDetails(), in: staging)
    }
  }

  @Test func neverChangesTheBooksFiles() async throws {
    let epub = EPUBFixture.book(
      metadata: "<dc:title>Moby-Dick</dc:title>", chapter: "<html><body><img/></body></html>")
    try epub.write(to: root)

    _ = try await preparer.prepare(book(), details: PackageDetails(), in: staging)

    #expect(try files(in: root) == epub.files)
  }

  // MARK: Details

  @Test func appliesTheDetailsBeforeTheFixes() async throws {
    try EPUBFixture.book(metadata: "<dc:title>Moby-Dick</dc:title>").write(to: root)

    let prepared = try await preparer.prepare(
      book(language: "es"), details: PackageDetails(language: "fr"), in: staging)

    #expect(prepared.applied == [.language])
    #expect(!prepared.fixes.contains(.addedLanguage))
    let package = try packageText(of: prepared)
    #expect(package.components(separatedBy: "<dc:language>").count == 2)
    #expect(package.contains("<dc:language>fr</dc:language>"))
  }

  @Test func theFixesRunOnTheEditedPackage() async throws {
    var epub = EPUBFixture.book()
    epub[text: "OEBPS/content.opf"] = epub[text: "OEBPS/content.opf"]?.replacing(
      #"<?xml version="1.0" encoding="utf-8"?>"#, with: "")
    try epub.write(to: root)

    let prepared = try await preparer.prepare(
      book(), details: PackageDetails(title: "Moby Dick"), in: staging)

    #expect(prepared.applied == [.title])
    #expect(prepared.fixes == [.addedXMLDeclaration])
    let package = try packageText(of: prepared)
    #expect(package.hasPrefix(XMLDeclarationFix.declaration))
    #expect(package.contains("<dc:title>Moby Dick</dc:title>"))
  }

  @Test func stagedZipHoldsTheEditedPackageAndCover() async throws {
    var epub = EPUBFixture.book(
      manifest: EPUBFixture.manifest
        + #"<item id="art" href="cover.jpg" media-type="image/jpeg" properties="cover-image"/>"#)
    epub.files["OEBPS/cover.jpg"] = try Self.image(.jpeg, width: 4)
    try epub.write(to: root)
    let cover = try Self.image(.jpeg, width: 8)
    let coverURL = folder.appending(path: "edit-cover.jpg")
    try cover.write(to: coverURL)

    let prepared = try await preparer.prepare(
      book(), details: PackageDetails(title: "Moby Dick", cover: coverURL), in: staging)

    #expect(prepared.applied == [.title, .cover])
    #expect(
      localHeaders(in: try Data(contentsOf: prepared.url)).map(\.name)
        == [
          "mimetype", "META-INF/container.xml", "OEBPS/chapter1.xhtml", "OEBPS/content.opf",
          "OEBPS/cover.jpg",
        ])
    let files = try unzipped(prepared.url)
    #expect(files["OEBPS/cover.jpg"] == cover)
    #expect(try packageText(of: prepared).contains("<dc:title>Moby Dick</dc:title>"))
    #expect(files["OEBPS/chapter1.xhtml"] == epub.files["OEBPS/chapter1.xhtml"])
  }

  @Test func aCoverTheBookDoesNotDeclareIsAddedAfterTheExistingEntries() async throws {
    let epub = EPUBFixture.book()
    try epub.write(to: root)
    let cover = try Self.image(.jpeg, width: 8)
    let coverURL = folder.appending(path: "edit-cover.jpg")
    try cover.write(to: coverURL)

    let prepared = try await preparer.prepare(
      book(), details: PackageDetails(cover: coverURL), in: staging)

    #expect(prepared.applied == [.cover])
    #expect(
      localHeaders(in: try Data(contentsOf: prepared.url)).map(\.name)
        == [
          "mimetype", "META-INF/container.xml", "OEBPS/chapter1.xhtml", "OEBPS/content.opf",
          "OEBPS/sendle-cover.jpg",
        ])
    #expect(try unzipped(prepared.url)["OEBPS/sendle-cover.jpg"] == cover)
    let package = try #require(
      OPFReader.package(
        Data(try packageText(of: prepared).utf8), at: "OEBPS/content.opf"))
    #expect(package.coverPath == "OEBPS/sendle-cover.jpg")
  }

  @Test func booksFolderIsUntouched() async throws {
    var epub = EPUBFixture.book(
      manifest: EPUBFixture.manifest
        + #"<item id="art" href="cover.jpg" media-type="image/jpeg" properties="cover-image"/>"#,
      chapter: "<html><body><img/></body></html>")
    epub.files["OEBPS/cover.jpg"] = try Self.image(.jpeg, width: 4)
    try epub.write(to: root)
    let coverURL = folder.appending(path: "edit-cover.jpg")
    try Self.image(.jpeg, width: 8).write(to: coverURL)
    let before = try digests(in: root)

    let prepared = try await preparer.prepare(
      book(),
      details: PackageDetails(
        title: "Moby Dick", creator: "Melville, Herman", language: "fr", year: "1851",
        isbn: "9780306406157", cover: coverURL),
      in: staging)

    #expect(prepared.applied == [.title, .author, .language, .year, .isbn, .cover])
    #expect(try digests(in: root) == before)
  }

  @Test func editionComesFromTheBooksOwnPackage() async throws {
    try EPUBFixture.book(
      metadata: EPUBFixture.metadata + """

        <dc:identifier>urn:isbn:9780306406157</dc:identifier>
        <dc:date>1851-10-18</dc:date>
        """
    ).write(to: root)

    let prepared = try await preparer.prepare(
      book(), details: PackageDetails(year: "2020", isbn: "9780141439518"), in: staging)

    #expect(prepared.applied == [.year, .isbn])
    #expect(
      prepared.edition
        == Edition(key: "urn:uuid:moby-dick", isbn: "9780306406157", year: "1851"))
    let package = try packageText(of: prepared)
    #expect(package.contains("urn:isbn:9780141439518"))
    #expect(!package.contains("9780306406157"))
  }

  @Test func unparseablePackageIsSentUneditedWithAWarning() async throws {
    var epub = EPUBFixture.book()
    epub[text: "OEBPS/content.opf"] = epub[text: "OEBPS/content.opf"]?.replacing(
      #"encoding="utf-8""#, with: #"encoding="ISO-8859-1""#)
    try epub.write(to: root)

    let prepared = try await preparer.prepare(
      book(), details: PackageDetails(title: "Moby Dick"), in: staging)

    #expect(prepared.applied.isEmpty)
    #expect(try unzipped(prepared.url)["OEBPS/content.opf"] == epub.files["OEBPS/content.opf"])
    #expect(
      log.summary == [
        "warning EPUB Couldn't write the details into the book "
          + "(its package document can't be edited); sending it as it is"
      ])
  }

  @Test func aPackageThatIsNotUTF8IsSentUneditedWithAWarning() async throws {
    var epub = EPUBFixture.book()
    epub.files["OEBPS/content.opf"] = try Self.latin1Package()
    try epub.write(to: root)

    let prepared = try await preparer.prepare(
      book(), details: PackageDetails(title: "Moby Dick"), in: staging)

    #expect(prepared.applied.isEmpty)
    #expect(try unzipped(prepared.url)["OEBPS/content.opf"] == epub.files["OEBPS/content.opf"])
    #expect(
      log.summary == [
        "warning EPUB Couldn't write the details into the book "
          + "(its package document can't be edited); sending it as it is"
      ])
  }

  @Test func sendsAPackageInAnotherEncodingAsItIsWhenThereAreNoDetails() async throws {
    var epub = EPUBFixture.book()
    epub.files["OEBPS/content.opf"] = try Self.latin1Package()
    try epub.write(to: root)

    let prepared = try await preparer.prepare(book(), details: PackageDetails(), in: staging)

    #expect(try unzipped(prepared.url)["OEBPS/content.opf"] == epub.files["OEBPS/content.opf"])
    #expect(log.summary.isEmpty)
  }

  @Test func anUnreadableCoverIsWarnedAboutAndTheOtherDetailsStillGo() async throws {
    try EPUBFixture.book().write(to: root)
    let gone = folder.appending(path: "gone.jpg")

    let prepared = try await preparer.prepare(
      book(), details: PackageDetails(title: "Moby Dick", cover: gone), in: staging)

    #expect(prepared.applied == [.title])
    #expect(try packageText(of: prepared).contains("<dc:title>Moby Dick</dc:title>"))
    #expect(log.summary.count == 1)
    #expect(
      log.summary.first?.hasPrefix(
        "warning EPUB Couldn't read the new cover (") == true)
    #expect(log.summary.first?.hasSuffix("); sending the book with its own") == true)
  }

  @Test func stopsWhenCancelled() async throws {
    try EPUBFixture.book().write(to: root)

    let book = book()

    let task = Task { [preparer, staging] in
      withUnsafeCurrentTask { $0?.cancel() }
      return try await preparer.prepare(book, details: PackageDetails(), in: staging)
    }

    await #expect(throws: SendFailure.cancelled) { try await task.value }
  }

  private func book(at url: URL? = nil, language: String? = "en") -> Book {
    .fixture(language: language, fileURL: url ?? root)
  }

  private func packageText(of prepared: PreparedFile) throws -> String {
    String(decoding: try unzipped(prepared.url)["OEBPS/content.opf"] ?? Data(), as: UTF8.self)
  }

  /// The SHA-256 of every regular file under `root`, by relative path.
  private func digests(in root: URL) throws -> [String: String] {
    try files(in: root).mapValues {
      SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined()
    }
  }

  /// A package document in ISO-8859-1 whose title holds a byte that isn't UTF-8.
  private static func latin1Package() throws -> Data {
    let text = EPUBFixture.package(
      metadata:
        "<dc:identifier id=\"id\">urn:uuid:moby-dick</dc:identifier><dc:title>Caf\u{E9}</dc:title>",
      manifest: EPUBFixture.manifest
    ).replacing("utf-8", with: "iso-8859-1")
    return try #require(text.data(using: .isoLatin1))
  }

  /// A solid red image, `width` by 6 pixels, so images of different widths differ in bytes.
  private static func image(_ type: UTType, width: Int) throws -> Data {
    struct Failure: Error {}
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil, width: width, height: 6, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw Failure() }
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: 6))
    let data = NSMutableData()
    guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithData(
        data as CFMutableData, type.identifier as CFString, 1, nil)
    else { throw Failure() }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw Failure() }
    return data as Data
  }

  private func unzipped(_ archive: URL) throws -> [String: Data] {
    let out = folder.appending(path: "unzipped-\(UUID().uuidString)", directoryHint: .isDirectory)
    #expect(
      try run(
        "/usr/bin/ditto",
        ["-x", "-k", archive.path(percentEncoded: false), out.path(percentEncoded: false)]
      ).status == 0)
    return try files(in: out)
  }

  /// Every regular file under `root`, by relative path.
  private func files(in root: URL) throws -> [String: Data] {
    var files: [String: Data] = [:]
    for path in try FileManager.default.subpathsOfDirectory(
      atPath: root.path(percentEncoded: false))
    {
      let url = root.appending(path: path)
      guard (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true else {
        continue
      }
      files[path] = try Data(contentsOf: url)
    }
    return files
  }
}

extension EPUBFixture {
  /// The fixture's files with `mimetype` first, ready for `writeArchive`.
  var archiveEntries: [(String, Data)] {
    files.sorted { lhs, rhs in
      lhs.key == "mimetype" || (rhs.key != "mimetype" && lhs.key < rhs.key)
    }.map { ($0.key, $0.value) }
  }
}
