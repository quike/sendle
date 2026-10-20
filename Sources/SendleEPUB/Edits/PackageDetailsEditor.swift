import Foundation
import SendleDomain

/// Writes the details a send carries into the text of a book's package document, following the
/// rules in Spike B §5 and spec §5.3.
package struct PackageDetailsEditor {
  package struct Result: Equatable {
    package var text: String
    package var applied: [PackageDetail]
    /// Bytes to write at an archive path: the declared cover overwritten, or one added.
    package var coverFile: (path: String, data: Data)?

    package static func == (lhs: Result, rhs: Result) -> Bool {
      lhs.text == rhs.text && lhs.applied == rhs.applied
        && lhs.coverFile?.path == rhs.coverFile?.path && lhs.coverFile?.data == rhs.coverFile?.data
    }
  }

  /// Nil when there is something to write but the text can't be parsed; the caller sends the book
  /// unedited.
  package static func apply(
    _ details: PackageDetails, to text: String, at path: String, package: EPUBPackage,
    coverImage: Data?
  ) -> Result? {
    guard !details.isEmpty else { return Result(text: text, applied: []) }
    guard let document = PackageDocument(text) else { return nil }
    var applied: [PackageDetail] = []
    if let title = details.title {
      write(title: title, in: document)
      applied.append(.title)
    }
    if let creator = details.creator {
      write(creator: creator, in: document)
      applied.append(.author)
    }
    if let language = details.language {
      write(language: language, in: document)
      applied.append(.language)
    }
    if let year = details.year {
      write(year: year, in: document)
      applied.append(.year)
    }
    if let isbn = details.isbn {
      write(isbn: isbn, in: document)
      applied.append(.isbn)
    }
    var coverFile: (path: String, data: Data)?
    if details.cover != nil, let coverImage {
      coverFile = write(cover: coverImage, in: document, at: path, package: package)
      if coverFile != nil { applied.append(.cover) }
    }
    return Result(
      text: applied.isEmpty ? text : document.text, applied: applied, coverFile: coverFile)
  }

  /// The main title, refined as `title-type main` or else the first, holds `title`; every other
  /// title and the old title's sort keys go.
  private static func write(title: String, in document: PackageDocument) {
    let titles = document.dublinCore("title")
    let main =
      titles.first { candidate in
        document.refinements(of: candidate).contains {
          $0.attributeValue("property") == "title-type" && $0.trimmedText == "main"
        }
      } ?? titles.first
    for other in titles where other !== main {
      removeWithRefinements(other, in: document)
    }
    document.metas(named: "calibre:title_sort").forEach { $0.detach() }
    guard let main else {
      document.metadata.addChild(document.newDublinCore("title", text: title))
      return
    }
    main.stringValue = title
    main.removeOPFAttribute("file-as")
    document.refinements(of: main)
      .filter { $0.attributeValue("property") == "file-as" }
      .forEach { $0.detach() }
  }

  /// One creator in the first author's place replaces every creator whose role is `aut` or
  /// missing. Creators in other roles become contributors, because boko lists every creator as an
  /// author.
  private static func write(creator: String, in document: PackageDocument) {
    let creators = document.dublinCore("creator")
    let authors = creators.filter { (role(of: $0, in: document) ?? "aut") == "aut" }
    let added = document.newDublinCore("creator", text: creator)
    var nodes = [added]
    if document.isEPUB3 {
      let id = document.unusedID("sendle-author")
      added.addAttribute(PackageDocument.attribute("id", id))
      nodes.append(
        document.newElement(
          "meta", in: document.metadata,
          attributes: [("refines", "#\(id)"), ("property", "role"), ("scheme", "marc:relators")],
          text: "aut"))
    } else {
      added.addAttribute(document.newOPFAttribute("role", "aut"))
    }
    for node in nodes {
      if let anchor = authors.first ?? creators.first {
        document.insert(node, before: anchor)
      } else {
        document.metadata.addChild(node)
      }
    }
    for old in creators {
      if authors.contains(where: { $0 === old }) {
        removeWithRefinements(old, in: document)
      } else {
        document.rename(old, to: "contributor")
      }
    }
    document.metas(named: "calibre:author_link_map").forEach { $0.detach() }
  }

  private static func write(language: String, in document: PackageDocument) {
    let languages = document.dublinCore("language")
    guard let first = languages.first else {
      document.metadata.addChild(document.newDublinCore("language", text: language))
      return
    }
    first.stringValue = language
    languages.dropFirst().forEach { $0.detach() }
  }

  /// The first date becomes the year unless it already falls in it.
  private static func write(year: String, in document: PackageDocument) {
    guard let date = document.dublinCore("date").first else {
      document.metadata.addChild(document.newDublinCore("date", text: year))
      return
    }
    let digits = date.trimmedText.prefix { $0.isASCII && $0.isNumber }
    if digits != year { date.stringValue = year }
  }

  /// The first ISBN identifier other than the package's unique identifier, which never changes,
  /// holds `isbn` in its own style; without one, an identifier is added.
  private static func write(isbn: String, in document: PackageDocument) {
    let existing = document.dublinCore("identifier").first {
      isISBN($0) && !document.isUniqueIdentifier($0)
    }
    guard let existing else {
      document.metadata.addChild(document.newDublinCore("identifier", text: "urn:isbn:\(isbn)"))
      return
    }
    let isURN = existing.trimmedText.lowercased().hasPrefix("urn:isbn:")
    existing.stringValue = isURN ? "urn:isbn:\(isbn)" : isbn
  }

  /// A declared JPEG or PNG is overwritten in its own type. Otherwise `sendle-cover.jpg` is added
  /// next to the package and declared as the cover in place of any other.
  private static func write(
    cover image: Data, in document: PackageDocument, at path: String, package: EPUBPackage
  ) -> (path: String, data: Data)? {
    if let declared = package.items.first(where: { $0.path == package.coverPath }),
      let data = CoverImage.data(from: image, mediaType: declared.mediaType)
    {
      return (declared.path, data)
    }
    guard let manifest = document.manifest,
      let data = CoverImage.data(from: image, mediaType: "image/jpeg")
    else { return nil }
    let (id, name, archivePath) = unusedCoverName(in: document, at: path, package: package)
    for item in manifest.childElements where item.localName == "item" {
      guard
        let properties = item.attributeValue("properties")?.split(whereSeparator: \.isWhitespace),
        properties.contains("cover-image")
      else { continue }
      let rest = properties.filter { $0 != "cover-image" }.joined(separator: " ")
      if rest.isEmpty {
        item.removeAttribute(forName: "properties")
      } else {
        item.attribute(forName: "properties")?.stringValue = rest
      }
    }
    var attributes = [("id", id), ("href", name), ("media-type", "image/jpeg")]
    if document.isEPUB3 { attributes.append(("properties", "cover-image")) }
    manifest.addChild(document.newElement("item", in: manifest, attributes: attributes))
    document.metas(named: "cover").forEach { $0.detach() }
    document.metadata.addChild(
      document.newElement(
        "meta", in: document.metadata, attributes: [("name", "cover"), ("content", id)]))
    return (archivePath, data)
  }

  private static func unusedCoverName(
    in document: PackageDocument, at path: String, package: EPUBPackage
  ) -> (id: String, name: String, path: String) {
    let directory = ArchivePath.directory(of: path)
    let paths = Set(package.items.map(\.path))
    var number = 1
    while true {
      let id = number == 1 ? "sendle-cover" : "sendle-cover-\(number)"
      let name = "\(id).jpg"
      let archivePath = directory.isEmpty ? name : "\(directory)/\(name)"
      if !document.isTaken(id: id), !paths.contains(archivePath) {
        return (document.unusedID(id), name, archivePath)
      }
      number += 1
    }
  }

  private static func removeWithRefinements(_ element: XMLElement, in document: PackageDocument) {
    document.refinements(of: element).forEach { $0.detach() }
    element.detach()
  }

  private static func role(of creator: XMLElement, in document: PackageDocument) -> String? {
    let role =
      creator.opfAttributeValue("role")
      ?? document.refinements(of: creator).first { $0.attributeValue("property") == "role" }?
      .stringValue
    let trimmed = role?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return trimmed?.isEmpty == false ? trimmed : nil
  }

  /// As `OPFReader` recognises an ISBN identifier.
  private static func isISBN(_ identifier: XMLElement) -> Bool {
    let scheme = identifier.opfAttributeValue("scheme") ?? identifier.attributeValue("scheme")
    let text = identifier.trimmedText.lowercased()
    return scheme?.lowercased() == "isbn" || text.hasPrefix("urn:isbn:") || text.hasPrefix("isbn:")
  }
}

extension XMLElement {
  fileprivate var trimmedText: String {
    (stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
