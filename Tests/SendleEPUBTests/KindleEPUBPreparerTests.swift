import Foundation
import SendleDomain
import SendleEPUB
import SendleTestSupport
import Testing

struct KindleEPUBPreparerTests {
  let folder: URL
  let staging: URL
  let root: URL
  let preparer = KindleEPUBPreparer()

  init() throws {
    folder = try makeTemporaryDirectory()
    staging = try makeTemporaryDirectory()
    root = folder.appending(path: "Moby-Dick.epub", directoryHint: .isDirectory)
  }

  @Test func packagesACleanBookAsItIs() async throws {
    let epub = EPUBFixture.book()
    try epub.write(to: root)

    let prepared = try await preparer.prepare(book(), in: staging)

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

    let prepared = try await preparer.prepare(book(), in: staging)

    #expect(prepared.edition?.key == "urn:uuid:moby-dick")
  }

  @Test func leavesOutApplesAdditions() async throws {
    var epub = EPUBFixture.book()
    epub.files["iTunesMetadata.plist"] = Data("plist".utf8)
    epub.files["OEBPS/.DS_Store"] = Data("finder".utf8)
    try epub.write(to: root)

    let prepared = try await preparer.prepare(book(), in: staging)

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

    let prepared = try await preparer.prepare(book(language: "es"), in: staging)

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

    let prepared = try await preparer.prepare(book(), in: staging)

    #expect(try unzipped(prepared.url)["OEBPS/chapter1.xhtml"] == latin1)
    #expect(prepared.fixes.isEmpty)
  }

  @Test func sendsUTF16DocumentsByteForByte() async throws {
    var epub = EPUBFixture.book()
    let utf16 = try #require("<html><body><img/></body></html>".data(using: .utf16LittleEndian))
    epub.files["OEBPS/chapter1.xhtml"] = utf16
    try epub.write(to: root)

    let prepared = try await preparer.prepare(book(), in: staging)

    #expect(try unzipped(prepared.url)["OEBPS/chapter1.xhtml"] == utf16)
    #expect(prepared.fixes.isEmpty)
  }

  @Test func unzipsAZippedEPUBFirst() async throws {
    let epub = EPUBFixture.book(metadata: "<dc:title>Moby-Dick</dc:title>")
    let file = folder.appending(path: "Zipped.epub")
    try writeArchive(epub.archiveEntries, to: file)

    let prepared = try await preparer.prepare(book(at: file), in: staging)

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
      try await preparer.prepare(book(at: file), in: staging)
    }
  }

  @Test func reportsAMissingBook() async {
    await #expect(throws: SendFailure.missing) {
      try await preparer.prepare(book(at: folder.appending(path: "Gone.epub")), in: staging)
    }
  }

  @Test func reportsABookWithoutAPackageAsInvalid() async throws {
    var epub = EPUBFixture.book()
    epub.files["META-INF/container.xml"] = nil
    try epub.write(to: root)

    await #expect(throws: SendFailure.invalidBook("Its package document is missing or unreadable"))
    {
      try await preparer.prepare(book(), in: staging)
    }
  }

  @Test func neverChangesTheBooksFiles() async throws {
    let epub = EPUBFixture.book(
      metadata: "<dc:title>Moby-Dick</dc:title>", chapter: "<html><body><img/></body></html>")
    try epub.write(to: root)

    _ = try await preparer.prepare(book(), in: staging)

    #expect(try files(in: root) == epub.files)
  }

  @Test func stopsWhenCancelled() async throws {
    try EPUBFixture.book().write(to: root)

    let book = book()

    let task = Task { [preparer, staging] in
      withUnsafeCurrentTask { $0?.cancel() }
      return try await preparer.prepare(book, in: staging)
    }

    await #expect(throws: SendFailure.cancelled) { try await task.value }
  }

  private func book(at url: URL? = nil, language: String? = "en") -> Book {
    .fixture(language: language, fileURL: url ?? root)
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
