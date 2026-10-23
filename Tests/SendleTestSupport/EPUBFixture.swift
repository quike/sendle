import Foundation

/// An unzipped EPUB described as text, written to disk by tests.
public struct EPUBFixture: Sendable {
  public var files: [String: Data]

  public init(files: [String: Data]) {
    self.files = files
  }

  /// A small valid EPUB 3 with one chapter, `OEBPS/chapter1.xhtml`.
  public static func book(
    metadata: String = EPUBFixture.metadata,
    manifest: String = EPUBFixture.manifest,
    chapter: String = EPUBFixture.chapter
  ) -> EPUBFixture {
    EPUBFixture(files: [
      "mimetype": Data("application/epub+zip".utf8),
      "META-INF/container.xml": Data(container.utf8),
      "OEBPS/content.opf": Data(package(metadata: metadata, manifest: manifest).utf8),
      "OEBPS/chapter1.xhtml": Data(chapter.utf8),
    ])
  }

  public static let container = """
    <?xml version="1.0" encoding="UTF-8"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles>
        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
      </rootfiles>
    </container>
    """

  public static let metadata = """
    <dc:identifier id="id">urn:uuid:moby-dick</dc:identifier>
    <dc:title>Moby-Dick</dc:title>
    <dc:language>en</dc:language>
    """

  public static let manifest = """
    <item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
    """

  public static let chapter = """
    <?xml version="1.0" encoding="utf-8"?>
    <html xmlns="http://www.w3.org/1999/xhtml"><head><title>One</title></head>
    <body><p>Call me Ishmael.</p></body></html>
    """

  public static func package(metadata: String, manifest: String) -> String {
    """
    <?xml version="1.0" encoding="utf-8"?>
    <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
    <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    \(metadata)
    </metadata>
    <manifest>
    \(manifest)
    </manifest>
    <spine><itemref idref="chapter1"/></spine>
    </package>
    """
  }

  public subscript(text path: String) -> String? {
    get { files[path].flatMap { String(data: $0, encoding: .utf8) } }
    set { files[path] = newValue.map { Data($0.utf8) } }
  }

  /// Writes every file under `root`, creating folders as needed, and returns `root`.
  @discardableResult
  public func write(to root: URL) throws -> URL {
    for (path, data) in files {
      let url = root.appending(path: path)
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: url)
    }
    return root
  }
}
