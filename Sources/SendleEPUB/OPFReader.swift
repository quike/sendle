import Foundation
import SendleDomain

/// What Sendle needs from an EPUB's package document. Paths are archive paths: relative to the
/// book's root, percent-decoded, separated by `/`.
package struct EPUBPackage: Hashable, Sendable {
  package struct Item: Hashable, Sendable {
    package let id: String
    package let path: String
    package let mediaType: String
    package let properties: Set<String>

    package init(id: String, path: String, mediaType: String, properties: Set<String>) {
      self.id = id
      self.path = path
      self.mediaType = mediaType
      self.properties = properties
    }
  }

  package let path: String
  package let items: [Item]
  package let coverPath: String?
  package let hasLanguage: Bool
  package let edition: Edition

  package init(
    path: String, items: [Item], coverPath: String?, hasLanguage: Bool, edition: Edition = Edition()
  ) {
    self.path = path
    self.items = items
    self.coverPath = coverPath
    self.hasLanguage = hasLanguage
    self.edition = edition
  }
}

public enum OPFReader {
  /// The cover image of an unzipped EPUB, or nil when the book declares none or the file it names
  /// isn't a regular file inside the book.
  public static func coverImage(inEPUBAt root: URL) -> URL? {
    guard let cover = package(inEPUBAt: root)?.coverPath else { return nil }
    let url = root.appending(path: cover)
    let resolved = url.resolvingSymlinksInPath().pathComponents
    let book = root.resolvingSymlinksInPath().pathComponents
    guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
      resolved.count > book.count, resolved.starts(with: book)
    else { return nil }
    return url
  }

  /// Finds the package document through `META-INF/container.xml` and reads it.
  package static func package(inEPUBAt root: URL) -> EPUBPackage? {
    guard
      let container = BookFile.contents(of: root.appending(path: "META-INF/container.xml")),
      let path = packagePath(inContainer: container),
      let document = BookFile.contents(of: root.appending(path: path))
    else { return nil }
    return package(document, at: path)
  }

  package static func packagePath(inContainer data: Data) -> String? {
    let reader = ContainerReader()
    parse(data, with: reader)
    return reader.fullPath.flatMap { ArchivePath.resolve($0, from: "") }
  }

  package static func package(_ data: Data, at path: String) -> EPUBPackage? {
    let reader = PackageReader()
    guard parse(data, with: reader) else { return nil }
    let directory = ArchivePath.directory(of: path)
    let items = reader.items.compactMap { item in
      ArchivePath.resolve(item.href, from: directory).map {
        EPUBPackage.Item(
          id: item.id, path: $0, mediaType: item.mediaType, properties: item.properties)
      }
    }
    let epub3Cover = items.first { $0.properties.contains("cover-image") }
    let epub2Cover = reader.coverID.flatMap { id in
      items.first { $0.id == id && $0.mediaType.hasPrefix("image/") }
    }
    return EPUBPackage(
      path: path, items: items, coverPath: (epub3Cover ?? epub2Cover)?.path,
      hasLanguage: reader.hasLanguage, edition: edition(from: reader))
  }

  /// The key is the identifier the package names as unique, else the ISBN.
  private static func edition(from reader: PackageReader) -> Edition {
    let isbn = reader.identifiers.lazy.compactMap { identifier -> String? in
      let text = identifier.text.lowercased()
      guard
        identifier.scheme?.lowercased() == "isbn" || text.hasPrefix("urn:isbn:")
          || text.hasPrefix("isbn:")
      else { return nil }
      return ISBN.normalised(identifier.text)
    }.first
    let unique = reader.uniqueIdentifier.flatMap { id in
      reader.identifiers.first { $0.id == id }?.text
    }
    return Edition(
      key: unique.flatMap { $0.isEmpty ? nil : $0 } ?? isbn, isbn: isbn,
      publisher: reader.publisher, year: reader.year)
  }

  @discardableResult
  private static func parse(_ data: Data, with delegate: some XMLParserDelegate) -> Bool {
    let parser = XMLParser(data: data)
    parser.shouldProcessNamespaces = true
    parser.shouldResolveExternalEntities = false
    parser.delegate = delegate
    return parser.parse()
  }
}

private final class ContainerReader: NSObject, XMLParserDelegate {
  var fullPath: String?

  func parser(
    _ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
    qualifiedName: String?, attributes: [String: String]
  ) {
    guard fullPath == nil, element == "rootfile", let path = attributes["full-path"] else { return }
    fullPath = path
  }
}

private final class PackageReader: NSObject, XMLParserDelegate {
  struct RawItem {
    let id: String
    let href: String
    let mediaType: String
    let properties: Set<String>
  }

  struct Identifier {
    let id: String?
    let scheme: String?
    let text: String
  }

  private struct Field {
    let name: String
    let id: String?
    let scheme: String?
    var text = ""
  }

  private static let dublinCore = "http://purl.org/dc/elements/1.1/"
  private static let fields: Set<String> = ["language", "identifier", "publisher", "date"]

  var items: [RawItem] = []
  var coverID: String?
  var hasLanguage = false
  var uniqueIdentifier: String?
  var identifiers: [Identifier] = []
  var publisher: String?
  /// Four digits from the first `dc:date`, when it starts with them.
  var year: String?
  private var sawDate = false
  private var field: Field?

  func parser(
    _ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
    qualifiedName: String?, attributes: [String: String]
  ) {
    switch element {
    case "package":
      uniqueIdentifier = attributes["unique-identifier"]
    case "item":
      guard let id = attributes["id"], let href = attributes["href"] else { return }
      let properties = (attributes["properties"] ?? "").split(whereSeparator: \.isWhitespace)
      items.append(
        RawItem(
          id: id, href: href, mediaType: attributes["media-type"] ?? "",
          properties: Set(properties.map(String.init))))
    case "meta" where attributes["name"] == "cover":
      coverID = coverID ?? attributes["content"]
    case _ where namespaceURI == Self.dublinCore && Self.fields.contains(element):
      field = Field(
        name: element, id: attributes["id"],
        scheme: attributes["scheme"] ?? attributes["opf:scheme"])
    default:
      break
    }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    field?.text.append(string)
  }

  func parser(
    _ parser: XMLParser, didEndElement element: String, namespaceURI: String?,
    qualifiedName: String?
  ) {
    guard let finished = field, finished.name == element else { return }
    field = nil
    let text = finished.text.trimmingCharacters(in: .whitespacesAndNewlines)
    switch element {
    case "language":
      hasLanguage = hasLanguage || !text.isEmpty
    case "identifier":
      identifiers.append(Identifier(id: finished.id, scheme: finished.scheme, text: text))
    case "date":
      guard !sawDate else { return }
      sawDate = true
      let digits = text.prefix { $0.isASCII && $0.isNumber }
      year = digits.count == 4 ? String(digits) : nil
    default:
      if publisher == nil, !text.isEmpty { publisher = text }
    }
  }
}
