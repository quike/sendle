import CoreGraphics
import Foundation
import ImageIO
import SendleDomain
import SendleEPUB
import SendleTestSupport
import Testing
import UniformTypeIdentifiers

@Suite(.timeLimit(.minutes(1)))
struct PackageDetailsEditorTests {
  private let path = "OEBPS/content.opf"
  private let coverURL = URL(filePath: "/Edits/edit-covers/book-1-0123456789ab.jpg")

  // MARK: Title

  @Test func titleReplacesTheMainTitleAndDropsSubtitlesAndTheirRefinements() throws {
    let text = EPUBFixture.package(
      metadata: """
        <dc:identifier id="id">urn:uuid:moby-dick</dc:identifier>
        <dc:title id="subtitle">A Subtitle</dc:title>
        <meta refines="#subtitle" property="title-type">subtitle</meta>
        <dc:title id="title">The Original &amp; Ugly Title</dc:title>
        <meta refines="#title" property="title-type">main</meta>
        <dc:title id="series">The Collection</dc:title>
        <meta refines="#series" property="title-type">collection</meta>
        <meta refines="#series" property="display-seq">2</meta>
        <dc:language>en</dc:language>
        """, manifest: EPUBFixture.manifest)

    let result = try apply(PackageDetails(title: "Édité: A Better Title & More"), to: text)

    let nodes = try metadata(of: result.text)
    #expect(
      nodes.named("dc:title")
        == [Node("dc:title", ["id": "title"], "Édité: A Better Title & More")])
    #expect(
      nodes.named("meta") == [
        Node("meta", ["refines": "#title", "property": "title-type"], "main")
      ])
    #expect(result.applied == [.title])

    let epub2 = epub2Sample.replacing(
      "<dc:title>Old EPUB2 Title</dc:title>",
      with: "<dc:title>Old EPUB2 Title</dc:title><dc:title>Second Title</dc:title>")
    let first = try apply(PackageDetails(title: "Nouveau titre"), to: epub2)
    #expect(try metadata(of: first.text).named("dc:title").map(\.text) == ["Nouveau titre"])
  }

  @Test func titleDropsFileAsAndCalibreTitleSort() throws {
    let result = try apply(PackageDetails(title: "A Better Title"), to: epub3Sample)

    let metas = try metadata(of: result.text).named("meta")
    #expect(!metas.contains { $0.attributes["refines"] == "#title" && $0.text != "main" })
    #expect(!metas.contains { $0.attributes["name"] == "calibre:title_sort" })
    #expect(metas.contains { $0.attributes["refines"] == "#author1" && $0.text == "Doe, John" })

    let epub2 = epub2Sample.replacing(
      "<dc:title>", with: #"<dc:title opf:file-as="EPUB2 Title, Old">"#)
    let edited = try apply(PackageDetails(title: "Nouveau titre"), to: epub2)
    #expect(
      try metadata(of: edited.text).named("dc:title") == [Node("dc:title", [:], "Nouveau titre")])
  }

  // MARK: Author

  @Test func authorReplacesAuthorCreatorsAndKeepsOtherRolesAsContributors() throws {
    let text = epub3Sample.replacing(
      #"<meta name="cover" content="cover-img"/>"#,
      with: #"<meta name="cover" content="cover-img"/>"# + "\n"
        + #"<meta name="calibre:author_link_map" content="{&quot;John Doe&quot;: &quot;&quot;}"/>"#)

    let result = try apply(PackageDetails(creator: "María José Override"), to: text)

    let nodes = try metadata(of: result.text)
    #expect(
      nodes.map(\.name) == [
        "dc:identifier", "dc:title", "meta", "meta", "dc:title", "meta", "dc:creator", "meta",
        "dc:contributor", "meta", "dc:language", "dc:publisher", "meta", "meta", "meta",
      ])
    #expect(
      nodes.named("dc:creator")
        == [Node("dc:creator", ["id": "sendle-author"], "María José Override")])
    let role = Node(
      "meta", ["refines": "#sendle-author", "property": "role", "scheme": "marc:relators"], "aut")
    #expect(nodes.firstIndex(of: role) == 7)
    #expect(
      nodes.named("dc:contributor") == [Node("dc:contributor", ["id": "ill"], "Ann Illustrator")])
    #expect(nodes.contains { $0.attributes["refines"] == "#ill" && $0.text == "ill" })
    #expect(!nodes.contains { ["#author1", "#author2"].contains($0.attributes["refines"]) })
    #expect(!nodes.contains { $0.attributes["name"] == "calibre:author_link_map" })
    #expect(result.applied == [.author])
  }

  @Test func epub2AuthorUsesOptRole() throws {
    let result = try apply(PackageDetails(creator: "Writer, New"), to: epub2Sample)

    let nodes = try metadata(of: result.text)
    #expect(
      nodes.map(\.name) == [
        "dc:title", "dc:creator", "dc:contributor", "dc:language", "dc:identifier",
      ])
    #expect(nodes.named("dc:creator") == [Node("dc:creator", ["opf:role": "aut"], "Writer, New")])
    #expect(
      nodes.named("dc:contributor")
        == [Node("dc:contributor", ["opf:role": "edt"], "Some Editor")])
  }

  // MARK: Language

  @Test func languageReplacesEveryDCLanguage() throws {
    let text = epub2Sample.replacing(#"version="2.0""#, with: #"version="2.0" xml:lang="fr""#)
      .replacing(
        "<dc:language>fr</dc:language>",
        with: "<dc:language>fr</dc:language>\n    <dc:language>en</dc:language>")

    let result = try apply(PackageDetails(language: "es"), to: text)

    #expect(try metadata(of: result.text).named("dc:language").map(\.text) == ["es"])
    #expect(result.text.contains(#"xml:lang="fr""#))
    #expect(result.applied == [.language])
  }

  // MARK: Year

  @Test func yearReplacesTheFirstDCDate() throws {
    let text = epub2Sample.replacing(
      "<dc:language>fr</dc:language>",
      with: """
        <dc:language>fr</dc:language>
            <dc:date opf:event="publication">1999-05-01</dc:date>
            <dc:date opf:event="modification">2020-01-01</dc:date>
        """)

    let result = try apply(PackageDetails(year: "2017"), to: text)

    #expect(
      try metadata(of: result.text).named("dc:date") == [
        Node("dc:date", ["opf:event": "publication"], "2017"),
        Node("dc:date", ["opf:event": "modification"], "2020-01-01"),
      ])
    #expect(result.applied == [.year])
  }

  @Test func yearKeepsADateInTheSameYear() throws {
    let text = EPUBFixture.package(
      metadata: EPUBFixture.metadata + "\n<dc:date>2017-03-01</dc:date>",
      manifest: EPUBFixture.manifest)

    let result = try apply(PackageDetails(year: "2017"), to: text)

    #expect(result.text == text)
    #expect(result.applied == [.year])
  }

  @Test func yearIsAddedWhenThereIsNoDate() throws {
    let text = EPUBFixture.package(metadata: EPUBFixture.metadata, manifest: EPUBFixture.manifest)

    let result = try apply(PackageDetails(year: "1851"), to: text)

    let nodes = try metadata(of: result.text)
    #expect(nodes.last == Node("dc:date", [:], "1851"))
    #expect(
      result.text.contains("<dc:language>en</dc:language><dc:date>1851</dc:date>\n</metadata>"))
  }

  // MARK: ISBN

  @Test func isbnReplacesAnExistingISBNIdentifierKeepingItsUrnStyle() throws {
    let text = EPUBFixture.package(
      metadata: EPUBFixture.metadata
        + #"<dc:identifier id="isbn">urn:isbn:9781861972712</dc:identifier>"#,
      manifest: EPUBFixture.manifest)

    let result = try apply(PackageDetails(isbn: "9780306406157"), to: text)

    #expect(
      try metadata(of: result.text).named("dc:identifier") == [
        Node("dc:identifier", ["id": "id"], "urn:uuid:moby-dick"),
        Node("dc:identifier", ["id": "isbn"], "urn:isbn:9780306406157"),
      ])
    #expect(result.applied == [.isbn])

    let epub2 = epub2Sample.replacing(
      "<dc:language>fr</dc:language>",
      with:
        #"<dc:language>fr</dc:language><dc:identifier opf:scheme="ISBN">1-86197-271-7</dc:identifier>"#
    )
    let plain = try apply(PackageDetails(isbn: "9780306406157"), to: epub2)
    #expect(
      try metadata(of: plain.text).named("dc:identifier").map(\.text) == [
        "9780306406157", "urn:uuid:11111111-2222-3333-4444-555555555555",
      ])
  }

  @Test func isbnIsAddedWhenTheOnlyISBNIsTheUniqueIdentifier() throws {
    let text = EPUBFixture.package(
      metadata: """
        <dc:identifier id="id">urn:isbn:9781861972712</dc:identifier>
        <dc:title>Moby-Dick</dc:title>
        """, manifest: EPUBFixture.manifest)

    let result = try apply(PackageDetails(isbn: "9780306406157"), to: text)

    #expect(
      try metadata(of: result.text).named("dc:identifier") == [
        Node("dc:identifier", ["id": "id"], "urn:isbn:9781861972712"),
        Node("dc:identifier", [:], "urn:isbn:9780306406157"),
      ])
  }

  // MARK: Cover

  @Test func coverOverwritesTheDeclaredJPEGPath() throws {
    let image = try Self.image(.png)

    let result = try apply(PackageDetails(cover: coverURL), to: epub3Sample, coverImage: image)

    let file = try #require(result.coverFile)
    #expect(file.path == "OEBPS/images/cover.jpg")
    #expect(Self.type(of: file.data) == .jpeg)
    #expect(try manifest(of: result.text) == manifest(of: epub3Sample))
    #expect(result.text == epub3Sample)
    #expect(result.applied == [.cover])
  }

  @Test func coverOverwritesADeclaredPNGAsPNG() throws {
    let text = EPUBFixture.package(
      metadata: EPUBFixture.metadata + #"<meta name="cover" content="art"/>"#,
      manifest: EPUBFixture.manifest
        + #"<item id="art" href="../Images/Cover.png" media-type="image/png"/>"#)

    let result = try apply(
      PackageDetails(cover: coverURL), to: text, coverImage: try Self.image(.jpeg))

    let file = try #require(result.coverFile)
    #expect(file.path == "Images/Cover.png")
    #expect(Self.type(of: file.data) == .png)
  }

  @Test func coverIsLeftAloneWithoutAReadableImage() throws {
    for image in [nil, Data("not an image".utf8)] {
      let result = try apply(PackageDetails(cover: coverURL), to: epub3Sample, coverImage: image)
      #expect(result.coverFile == nil)
      #expect(result.applied == [])
      #expect(result.text == epub3Sample)
    }
  }

  @Test func coverIsAddedWhenNoneIsDeclared() throws {
    let image = try Self.image(.jpeg)
    let epub3 = EPUBFixture.package(metadata: EPUBFixture.metadata, manifest: EPUBFixture.manifest)

    let added = try apply(PackageDetails(cover: coverURL), to: epub3, coverImage: image)

    #expect(added.coverFile?.path == "OEBPS/sendle-cover.jpg")
    #expect(added.coverFile.map { Self.type(of: $0.data) } == .jpeg)
    #expect(
      try manifest(of: added.text).last
        == Node(
          "item",
          [
            "id": "sendle-cover", "href": "sendle-cover.jpg", "media-type": "image/jpeg",
            "properties": "cover-image",
          ], ""))
    #expect(
      try metadata(of: added.text).last
        == Node("meta", ["name": "cover", "content": "sendle-cover"], ""))
    #expect(try reread(added.text).coverPath == "OEBPS/sendle-cover.jpg")
    #expect(added.applied == [.cover])

    let epub2 = try apply(PackageDetails(cover: coverURL), to: epub2Sample, coverImage: image)
    #expect(
      try manifest(of: epub2.text).last
        == Node(
          "item", ["id": "sendle-cover", "href": "sendle-cover.jpg", "media-type": "image/jpeg"],
          ""))
    #expect(try reread(epub2.text).coverPath == "OEBPS/sendle-cover.jpg")
  }

  @Test func coverIsAddedWhenTheDeclaredOneIsSVG() throws {
    let text = EPUBFixture.package(
      metadata: EPUBFixture.metadata + #"<meta name="cover" content="art"/>"#,
      manifest: EPUBFixture.manifest
        + #"<item id="art" href="cover.svg" media-type="image/svg+xml" properties="cover-image"/>"#
        + #"<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav cover-image"/>"#
    )

    let result = try apply(
      PackageDetails(cover: coverURL), to: text, coverImage: try Self.image(.png))

    #expect(result.coverFile?.path == "OEBPS/sendle-cover.jpg")
    #expect(result.coverFile.map { Self.type(of: $0.data) } == .jpeg)
    let items = try manifest(of: result.text)
    #expect(items.first { $0.attributes["id"] == "art" }?.attributes["properties"] == nil)
    #expect(items.first { $0.attributes["id"] == "nav" }?.attributes["properties"] == "nav")
    #expect(
      try metadata(of: result.text).filter { $0.attributes["name"] == "cover" }.map(
        \.attributes["content"]) == ["sendle-cover"])
    #expect(try reread(result.text).coverPath == "OEBPS/sendle-cover.jpg")
  }

  @Test func anAddedCoverGetsAnUnusedIDAndFileName() throws {
    let text = EPUBFixture.package(
      metadata: EPUBFixture.metadata,
      manifest: EPUBFixture.manifest
        + #"<item id="sendle-cover" href="chapter2.xhtml" media-type="application/xhtml+xml"/>"#
        + #"<item id="other" href="sendle-cover-2.jpg" media-type="image/gif"/>"#)

    let result = try apply(
      PackageDetails(cover: coverURL), to: text, coverImage: try Self.image(.jpeg))

    #expect(result.coverFile?.path == "OEBPS/sendle-cover-3.jpg")
    #expect(try manifest(of: result.text).last?.attributes["id"] == "sendle-cover-3")
  }

  // MARK: Fidelity

  @Test func keepsThePrologAndUntouchedBytes() throws {
    let prolog = """
      <?xml version="1.0" encoding="UTF-8" standalone="no"?>
      <!-- Made by hand -->

      """
    let text = prolog + epub2Sample.drop { $0 != "\n" }.dropFirst()
    #expect(try apply(PackageDetails(), to: text).text == text)
    #expect(try apply(PackageDetails(), to: text).applied == [])
    let retitled = try apply(PackageDetails(title: "Nouveau titre"), to: text)
    #expect(retitled.text == text.replacing("Old EPUB2 Title", with: "Nouveau titre"))

    let edited = try apply(PackageDetails(title: "A Better Title"), to: epub3Sample)
    let removed = [
      ##"<meta refines="#title" property="file-as">Original &amp; Ugly Title, The</meta>"##,
      #"<dc:title id="subtitle">A Subtitle</dc:title>"#,
      ##"<meta refines="#subtitle" property="title-type">subtitle</meta>"##,
      #"<meta name="calibre:title_sort" content="Original &amp; Ugly Title, The"/>"#,
    ]
    let expected = epub3Sample.split(separator: "\n", omittingEmptySubsequences: false)
      .filter { !removed.contains(String($0)) }
      .joined(separator: "\n")
      .replacing("The Original &amp; Ugly Title</dc:title>", with: "A Better Title</dc:title>")
    #expect(edited.text == expected)
  }

  // MARK: Other styles

  @Test func editsDefaultNamespaceDublinCore() throws {
    let dc = #"xmlns="http://purl.org/dc/elements/1.1/""#
    let opf = #"xmlns:opf="http://www.idpf.org/2007/opf""#
    let text = """
      <?xml version="1.0" encoding="utf-8"?>
      <package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="id">
      <metadata>
      <identifier \(dc) id="id">urn:uuid:moby-dick</identifier>
      <title \(dc)>Old Title</title>
      <creator \(dc) \(opf) opf:role="aut">Old Writer</creator>
      <creator \(dc) \(opf) opf:role="ill">Some Illustrator</creator>
      <language \(dc)>fr</language>
      </metadata>
      <manifest>
      <item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
      </manifest>
      <spine><itemref idref="chapter1"/></spine>
      </package>

      """
    let details = PackageDetails(
      title: "New Title", creator: "Writer, New", language: "es", year: "1999")

    let result = try apply(details, to: text)

    let nodes = try metadata(of: result.text)
    #expect(nodes.named("dc:title").map(\.text) == ["New Title"])
    #expect(nodes.named("dc:creator") == [Node("dc:creator", ["opf:role": "aut"], "Writer, New")])
    #expect(
      nodes.named("dc:contributor")
        == [Node("dc:contributor", ["opf:role": "ill"], "Some Illustrator")])
    #expect(nodes.named("dc:language").map(\.text) == ["es"])
    #expect(nodes.named("dc:date").map(\.text) == ["1999"])
    #expect(result.applied == [.title, .author, .language, .year])
    #expect(try reread(result.text).hasLanguage)
  }

  @Test func editsAroundCommentsAndCRLF() throws {
    let text = epub2Sample.replacing(
      "<dc:creator opf:role=\"aut\"",
      with: "<!-- The writers -->\n    <dc:creator opf:role=\"aut\""
    ).replacing("<dc:title>", with: "<dc:title><!-- as published -->")
      .replacing("\n", with: "\r\n")

    let result = try apply(PackageDetails(title: "Nouveau titre", creator: "Auteur"), to: text)

    #expect(result.text.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\r\n<package"))
    #expect(!result.text.replacing("\r\n", with: "").contains("\n"))
    #expect(result.text.contains("\r\n    <!-- The writers --><dc:creator"))
    #expect(result.text.contains("\r\n    <dc:language>fr</dc:language>\r\n"))
    #expect(result.text.hasSuffix("</package>\r\n"))
    let nodes = try metadata(of: result.text)
    #expect(nodes.named("dc:title").map(\.text) == ["Nouveau titre"])
    #expect(nodes.named("dc:creator").map(\.text) == ["Auteur"])
  }

  @Test func keepsEntities() throws {
    let text = epub3Sample.replacing(
      "<dc:publisher>Probe Press</dc:publisher>",
      with: "<dc:publisher>Caf&#233; &amp; Fils &lt;Paris&gt;</dc:publisher>")

    let result = try apply(PackageDetails(title: "Tom & Jerry <Live>"), to: text)

    #expect(result.text.contains("<dc:title id=\"title\">Tom &amp; Jerry &lt;Live&gt;</dc:title>"))
    #expect(
      result.text.contains(##"<meta refines="#author1" property="file-as">Doe, John</meta>"##))
    let nodes = try metadata(of: result.text)
    #expect(nodes.named("dc:publisher").map(\.text) == ["Café & Fils <Paris>"])
    #expect(nodes.named("dc:title").map(\.text) == ["Tom & Jerry <Live>"])
  }

  // MARK: Unusable input

  @Test func returnsNilForTextThatIsNotXML() throws {
    let package = try reread(epub2Sample)
    for text in ["", "not xml at all", "<package><metadata></package>", "<html/>"] {
      #expect(
        PackageDetailsEditor.apply(
          PackageDetails(title: "New"), to: text, at: path, package: package, coverImage: nil)
          == nil)
    }
  }

  @Test func returnsNilForAPackageDeclaredInAnotherEncoding() throws {
    let text = epub2Sample.replacing(#"encoding="UTF-8""#, with: #"encoding="ISO-8859-1""#)
    #expect(
      PackageDetailsEditor.apply(
        PackageDetails(title: "Été"), to: text, at: path, package: try reread(text),
        coverImage: nil) == nil)
  }

  // MARK: Helpers

  private func apply(
    _ details: PackageDetails, to text: String, coverImage: Data? = nil
  ) throws -> PackageDetailsEditor.Result {
    try #require(
      PackageDetailsEditor.apply(
        details, to: text, at: path, package: try reread(text), coverImage: coverImage))
  }

  private func reread(_ text: String) throws -> EPUBPackage {
    try #require(OPFReader.package(Data(text.utf8), at: path))
  }

  private func metadata(of text: String) throws -> [Node] {
    try children(of: "metadata", in: text)
  }

  private func manifest(of text: String) throws -> [Node] {
    try children(of: "manifest", in: text)
  }

  private func children(of name: String, in text: String) throws -> [Node] {
    let document = try XMLDocument(xmlString: text)
    let parent = try #require(
      document.rootElement()?.elements(forLocalName: name, uri: Node.opf).first)
    return (parent.children ?? []).compactMap { $0 as? XMLElement }.map(Node.init)
  }

  private static func image(_ type: UTType) throws -> Data {
    struct Failure: Error {}
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil, width: 4, height: 6, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw Failure() }
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 4, height: 6))
    let data = NSMutableData()
    guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithData(
        data as CFMutableData, type.identifier as CFString, 1, nil)
    else { throw Failure() }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw Failure() }
    return data as Data
  }

  private static func type(of data: Data) -> UTType? {
    CGImageSourceCreateWithData(data as CFData, nil)
      .flatMap { CGImageSourceGetType($0) as String? }
      .flatMap { UTType($0) }
  }
}

/// A child of `<metadata>` or `<manifest>`: "dc:title" for any Dublin Core element whatever its
/// prefix, else the local name, with its attributes by qualified name.
private struct Node: Equatable, CustomStringConvertible {
  static let opf = "http://www.idpf.org/2007/opf"
  static let dublinCore = "http://purl.org/dc/elements/1.1/"

  let name: String
  let attributes: [String: String]
  let text: String

  init(_ name: String, _ attributes: [String: String], _ text: String) {
    self.name = name
    self.attributes = attributes
    self.text = text
  }

  init(_ element: XMLElement) {
    let local = element.localName ?? ""
    name = element.uri == Self.dublinCore ? "dc:\(local)" : local
    attributes = Dictionary(
      (element.attributes ?? []).map { ($0.name ?? "", $0.stringValue ?? "") },
      uniquingKeysWith: { first, _ in first })
    text = element.stringValue ?? ""
  }

  var description: String { "\(name) \(attributes) \(text.debugDescription)" }
}

extension [Node] {
  fileprivate func named(_ name: String) -> [Node] { filter { $0.name == name } }
}

/// Spike B's awkward EPUB 3 sample: a subtitle, refinements, `calibre:title_sort`, two authors and
/// an illustrator, and a JPEG cover declared both ways.
private let epub3Sample = EPUBFixture.package(
  metadata: """
    <dc:identifier id="id">urn:uuid:7c0b5d0e-1f7a-4d43-9d3f-3a8f0f5b1a11</dc:identifier>
    <!-- Original title, as published -->
    <dc:title id="title">The Original &amp; Ugly Title</dc:title>
    <meta refines="#title" property="title-type">main</meta>
    <meta refines="#title" property="file-as">Original &amp; Ugly Title, The</meta>
    <dc:title id="subtitle">A Subtitle</dc:title>
    <meta refines="#subtitle" property="title-type">subtitle</meta>
    <dc:creator xmlns:opf="http://www.idpf.org/2007/opf" id="author1" opf:file-as="Doe, John">John Doe</dc:creator>
    <meta refines="#author1" property="role" scheme="marc:relators">aut</meta>
    <meta refines="#author1" property="file-as">Doe, John</meta>
    <dc:creator id="author2">Richard Roe</dc:creator>
    <meta refines="#author2" property="role" scheme="marc:relators">aut</meta>
    <dc:creator id="ill">Ann Illustrator</dc:creator>
    <meta refines="#ill" property="role" scheme="marc:relators">ill</meta>
    <dc:language>en</dc:language>
    <dc:publisher>Probe Press</dc:publisher>
    <meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>
    <meta name="cover" content="cover-img"/>
    <meta name="calibre:title_sort" content="Original &amp; Ugly Title, The"/>
    """,
  manifest: """
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="cover-img" href="images/cover.jpg" media-type="image/jpeg" properties="cover-image"/>
    <item id="cover" href="cover.xhtml" media-type="application/xhtml+xml"/>
    <item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    """)

/// Spike B's EPUB 2 sample: no cover, an author and an editor by `opf:role`, in French.
private let epub2Sample = """
  <?xml version="1.0" encoding="UTF-8"?>
  <package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="BookId">
    <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
      <dc:title>Old EPUB2 Title</dc:title>
      <dc:creator opf:role="aut" opf:file-as="Writer, Old">Old Writer</dc:creator>
      <dc:creator opf:role="edt">Some Editor</dc:creator>
      <dc:language>fr</dc:language>
      <dc:identifier id="BookId" opf:scheme="UUID">urn:uuid:11111111-2222-3333-4444-555555555555</dc:identifier>
    </metadata>
    <manifest>
      <item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
      <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    </manifest>
    <spine toc="ncx"><itemref idref="chapter1"/></spine>
  </package>

  """
