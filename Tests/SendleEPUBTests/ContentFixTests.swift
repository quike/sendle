import SendleDomain
import SendleEPUB
import Testing

struct BodyIDLinkFixTests {
  @Test func findsTheBodysID() {
    #expect(
      BodyIDLinkFix.bodyID(in: #"<html><body class="x" id="start"><p/></body></html>"#) == "start")
    #expect(BodyIDLinkFix.bodyID(in: "<html><body title='a > b' id='c1'></body></html>") == "c1")
    #expect(BodyIDLinkFix.bodyID(in: #"<html><body><p id="p1"/></body></html>"#) == nil)
  }

  @Test func dropsFragmentsThatPointAtABodyID() {
    let before = """
      <a href="chapter2.xhtml#c2">Next</a> <a href="../Text/chapter2.xhtml#p4">Here</a>
      <a href='#top'>Top</a> <a href="https://example.com/#c2">Web</a>
      """

    let after = BodyIDLinkFix.apply(
      to: before, at: "OEBPS/Text/chapter1.xhtml",
      bodyIDs: ["OEBPS/Text/chapter2.xhtml": "c2", "OEBPS/Text/chapter1.xhtml": "top"])

    #expect(
      after
        == """
        <a href="chapter2.xhtml">Next</a> <a href="../Text/chapter2.xhtml#p4">Here</a>
        <a href='chapter1.xhtml'>Top</a> <a href="https://example.com/#c2">Web</a>
        """)
  }

  @Test func rewritesNavigationPointsToo() {
    let ncx = #"<navPoint><content src="Text/chapter2.xhtml#c2"/></navPoint>"#

    #expect(
      BodyIDLinkFix.apply(
        to: ncx, at: "OEBPS/toc.ncx", bodyIDs: ["OEBPS/Text/chapter2.xhtml": "c2"])
        == #"<navPoint><content src="Text/chapter2.xhtml"/></navPoint>"#)
  }

  @Test func leavesDocumentsWithoutSuchLinksAlone() {
    #expect(
      BodyIDLinkFix.apply(
        to: #"<a href="b.xhtml#p1">x</a>"#, at: "a.xhtml", bodyIDs: ["b.xhtml": "b"])
        == nil)
  }

  @Test func escapesTheDocumentsOwnNameInASameDocumentLink() {
    #expect(
      BodyIDLinkFix.apply(
        to: ##"<a href="#top">Top</a>"##, at: "OEBPS/Chapter 1 & 2.xhtml",
        bodyIDs: ["OEBPS/Chapter 1 & 2.xhtml": "top"])
        == #"<a href="Chapter%201%20%26%202.xhtml">Top</a>"#)
  }
}

struct EmptyImageFixTests {
  @Test func removesImagesWithoutASource() {
    let before = """
      <p><img alt="a > b"/>One<img src="" />Two<img src="  "></img>Three\
      <img src="cover.jpg" alt="Cover"/><IMG ALT="x"></p>
      """

    #expect(
      EmptyImageFix.apply(to: before)
        == #"<p>OneTwoThree<img src="cover.jpg" alt="Cover"/></p>"#)
  }

  @Test func leavesImagesWithASourceAlone() {
    #expect(
      EmptyImageFix.apply(
        to:
          #"<img alt="x" src='a.png'/><img src=b.png><img src="d.png"></img><image href="c.png"/>"#)
        == nil)
  }
}

struct KindleFixerTests {
  let package = EPUBPackage(
    path: "OEBPS/content.opf",
    items: [
      .init(id: "c1", path: "OEBPS/one.xhtml", mediaType: "application/xhtml+xml", properties: []),
      .init(id: "c2", path: "OEBPS/two.xhtml", mediaType: "application/xhtml+xml", properties: []),
      .init(
        id: "ncx", path: "OEBPS/toc.ncx", mediaType: "application/x-dtbncx+xml", properties: []),
      .init(id: "img", path: "OEBPS/a.jpg", mediaType: "image/jpeg", properties: []),
    ],
    coverPath: nil,
    hasLanguage: false
  )

  @Test func listsTheMarkupDocuments() {
    #expect(
      KindleFixer.markupPaths(in: package)
        == ["OEBPS/content.opf", "OEBPS/one.xhtml", "OEBPS/two.xhtml", "OEBPS/toc.ncx"])
  }

  @Test func appliesEveryFixAndReportsEachOnce() {
    let documents = [
      "OEBPS/content.opf":
        #"<?xml version="1.0" encoding="utf-8"?><package><metadata></metadata></package>"#,
      "OEBPS/one.xhtml": #"<html><body><a href="two.xhtml#two">2</a><img/></body></html>"#,
      "OEBPS/two.xhtml": #"<?xml version="1.0" encoding="utf-8"?><html><body id="two"/></html>"#,
      "OEBPS/toc.ncx": #"<?xml version="1.0" encoding="utf-8"?><ncx/>"#,
    ]

    let result = KindleFixer(language: "fr").apply(to: documents, package: package)

    #expect(
      result.fixes == [
        .addedXMLDeclaration, .addedLanguage, .removedBodyIDLinks, .removedEmptyImages,
      ])
    #expect(Set(result.documents.keys) == ["OEBPS/content.opf", "OEBPS/one.xhtml"])
    #expect(
      result.documents["OEBPS/one.xhtml"]
        == XMLDeclarationFix.declaration + "\n"
        + #"<html><body><a href="two.xhtml">2</a></body></html>"#)
    #expect(result.documents["OEBPS/content.opf"]?.contains(">fr</dc:language>") == true)
  }

  @Test func reportsNothingForACleanBook() {
    let clean = #"<?xml version="1.0" encoding="utf-8"?><html><body/></html>"#
    let withLanguage = EPUBPackage(
      path: package.path, items: package.items, coverPath: nil, hasLanguage: true)

    let result = KindleFixer(language: nil).apply(
      to: [
        "OEBPS/one.xhtml": clean,
        "OEBPS/content.opf": #"<?xml version="1.0" encoding="utf-8"?><package/>"#,
      ],
      package: withLanguage)

    #expect(result.documents.isEmpty)
    #expect(result.fixes.isEmpty)
  }
}
